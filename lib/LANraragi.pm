package LANraragi;

use local::lib;

use open ':std', ':encoding(UTF-8)';

use Mojo::Base 'Mojolicious';
use Mojo::File;
use Mojo::JSON qw(decode_json encode_json);
use Storable;
use Sys::Hostname;
use Config;

use LANraragi::Utils::Generic qw(start_shinobu start_minion);
use LANraragi::Utils::Logging qw(get_logger get_logdir);
use LANraragi::Utils::Plugins qw(get_plugins);
use LANraragi::Utils::TempFolder qw(get_temp);
use LANraragi::Utils::Routing;
use LANraragi::Utils::Minion;

use LANraragi::Model::Search;
use LANraragi::Model::Config;

# This method will run once at server start
sub startup {
    my $self = shift;

    say "";
    say "";
    say "ｷﾀ━━━━━━(ﾟ∀ﾟ)━━━━━━!!!!!";

    # Load package.json to get version/vername/description
    my $packagejson = decode_json( Mojo::File->new('package.json')->slurp );

    my $version = $packagejson->{version};
    my $vername = $packagejson->{version_name};
    my $descstr = $packagejson->{description};

    # Use the hostname and osname for a sorta-unique set of secrets.
    $self->secrets( [ hostname(), $Config{"osname"}, 'oshino' ] );
    $self->plugin('RenderFile');

    # Set Template::Toolkit as default renderer so we can use the LRR templates
    $self->plugin('TemplateToolkit');
    $self->renderer->default_handler('tt2');

    #Remove upload limit
    $self->max_request_size(0);

    #Helper so controllers can reach the app's Redis DB quickly
    #(they still need to declare use Model::Config)
    $self->helper( LRR_CONF    => sub { LANraragi::Model::Config:: } );
    $self->helper( LRR_VERSION => sub { return $version; } );
    $self->helper( LRR_VERNAME => sub { return $vername; } );
    $self->helper( LRR_DESC    => sub { return $descstr; } );

    #Helper to build logger objects quickly
    $self->helper(
        LRR_LOGGER => sub {
            return get_logger( "LANraragi", "lanraragi" );
        }
    );

    #Check if a Redis server is running on the provided address/port
    eval { $self->LRR_CONF->get_redis->ping(); };
    if ($@) {
        say "(╯・_>・）╯︵ ┻━┻";
        say "您的Redis数据库目前没有运行。";
        say "程序将停止运行。";
        die;
    }

    # Catch Redis errors on our first connection. This is useful in case of temporary LOADING errors,
    # Where Redis lets us send commands but doesn't necessarily reply to them properly.
    # (https://github.com/redis/redis/issues/4624)
    while (1) {
        eval { $self->LRR_CONF->get_redis->keys('*') };

        last unless ($@);

        say "遇到Redis错误: $@";
        say "将在2秒后重试...";
        sleep 2;
    }

    # Check old settings and migrate them if needed
    if ( $self->LRR_CONF->get_redis->keys('LRR_*') ) {
        say "将旧版本设置迁移到新版本...";
        migrate_old_settings($self);
    }

    if ( $self->LRR_CONF->enable_devmode ) {
        $self->mode('development');
        $self->LRR_LOGGER->info("LANraragi $version (重新)启动。(调试模式)");

        my $logpath = get_logdir . "/mojo.log";

        #Tell the mojo logger to log to file
        $self->log->on(
            message => sub {
                my ( $time, $level, @lines ) = @_;

                open( my $fh, '>>', $logpath )
                  or die "无法打开文件 '$logpath' $!";

                my $l1 = $lines[0] // "";
                my $l2 = $lines[1] // "";
                print $fh "[Mojolicious] $l1 $l2 \n";
                close $fh;
            }
        );

    } else {
        $self->mode('production');
        $self->LRR_LOGGER->info("LANraragi $version 已启动。(生产模式)");
    }

    #Plugin listing
    my @plugins = get_plugins("metadata");
    foreach my $pluginfo (@plugins) {
        my $name = $pluginfo->{name};
        $self->LRR_LOGGER->info( "检测到插件: " . $name );
    }

    @plugins = get_plugins("script");
    foreach my $pluginfo (@plugins) {
        my $name = $pluginfo->{name};
        $self->LRR_LOGGER->info( "检测到脚本: " . $name );
    }

    @plugins = get_plugins("download");
    foreach my $pluginfo (@plugins) {
        my $name = $pluginfo->{name};
        $self->LRR_LOGGER->info( "检测到下载器: " . $name );
    }

    # Enable Minion capabilities in the app
    shutdown_from_pid( get_temp . "/minion.pid" );

    my $miniondb = $self->LRR_CONF->get_redisad . "/" . $self->LRR_CONF->get_miniondb;
    say "Minion将使用位于 $miniondb 的Redis数据库";
    $self->plugin( 'Minion' => { Redis => "redis://$miniondb" } );
    $self->LRR_LOGGER->info("成功连接到Minion数据库。");
    $self->minion->missing_after(5);    # Clean up older workers after 5 seconds of unavailability

    LANraragi::Utils::Minion::add_tasks( $self->minion );
    $self->LRR_LOGGER->debug("添加了Minion的任务");

    # Rebuild stat hashes
    # /!\ Enqueuing tasks must be done either before starting the worker, or once the IOLoop is started!
    # Anything else can cause weird database lockups.
    $self->minion->enqueue('build_stat_hashes');

    # Start a Minion worker in a subprocess
    start_minion($self);

    # Start File Watcher
    shutdown_from_pid( get_temp . "/shinobu.pid" );
    start_shinobu($self);

    # Hook to SIGTERM to cleanly kill minion+shinobu on server shutdown
    # As this is executed during before_dispatch, this code won't work if you SIGTERM without loading a single page!
    # (https://stackoverflow.com/questions/60814220/how-to-manage-myself-sigint-and-sigterm-signals)
    $self->hook(
        before_dispatch => sub {
            state $unused = add_sigint_handler();
        }
    );

    LANraragi::Utils::Routing::apply_routes($self);
    $self->LRR_LOGGER->info("路由完成！可以接收外来请求。");
}

sub shutdown_from_pid {
    my $file = shift;

    if ( -e $file && eval { retrieve($file); } ) {

        # Deserialize process
        my $oldproc = ${ retrieve($file) };
        my $pid     = $oldproc->pid;

        say "Killing process $pid from $file";
        $oldproc->kill();
        unlink($file);
    }
}

sub add_sigint_handler {
    my $old_int = $SIG{INT};
    $SIG{INT} = sub {
        shutdown_from_pid( get_temp . "/shinobu.pid" );
        shutdown_from_pid( get_temp . "/minion.pid" );

        \&$old_int;    # Calling the old handler to cleanly exit the server
      }
}

sub migrate_old_settings {
    my $self = shift;

    # Grab all LRR_* keys from LRR_CONF->get_redis and move them to the config DB
    my $redis     = $self->LRR_CONF->get_redis;
    my $config_db = $self->LRR_CONF->get_configdb;
    my @keys      = $redis->keys('LRR_*');

    foreach my $key (@keys) {
        say "Migrating $key to database $config_db";
        $redis->move( $key, $config_db );
    }

}

1;
