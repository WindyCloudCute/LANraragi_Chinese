package Shinobu;

# LANraragi File Watcher.
#  Uses inotify watches to keep track of filesystem happenings.
#  My main tasks are:
#
#    Tracking all files in the content folder and making sure they're sync'ed with the database
#    Automatically cleaning the temporary folder when it reaches a certain size
#
use strict;
use warnings;
use utf8;
use feature qw(say signatures);
no warnings 'experimental::signatures';

use FindBin;
use Parallel::Loops;
use Sys::CpuAffinity;
use Storable qw(lock_store);
use Mojo::JSON qw(to_json);

#As this is a new process, reloading the LRR libs into INC is needed.
BEGIN { unshift @INC, "$FindBin::Bin/../lib"; }

use Mojolicious;    # Needed by Model::Config to read the Redis address/port.
use File::ChangeNotify;
use File::Find;
use File::Basename;
use Encode;

use LANraragi::Utils::Database qw(redis_encode invalidate_cache compute_id);
use LANraragi::Utils::TempFolder qw(get_temp clean_temp_partial);
use LANraragi::Utils::Logging qw(get_logger);
use LANraragi::Utils::Generic qw(is_archive split_workload_by_cpu);

use LANraragi::Model::Config;
use LANraragi::Model::Plugins;
use LANraragi::Utils::Plugins;    # Needed here since Shinobu doesn't inherit from the main LRR package
use LANraragi::Model::Search;     # idem

# Logger and Database objects
my $logger = get_logger( "Shinobu", "shinobu" );

#Subroutine for new and deleted files that takes inotify events
my $inotifysub = sub {
    my $e    = shift;
    my $name = $e->path;
    my $type = $e->type;
    $logger->debug("收到 $name 上的 inotify 事件 $type");

    if ( $type eq "create" || $type eq "modify" ) {
        new_file_callback($name);
    }

    if ( $type eq "delete" ) {
        deleted_file_callback($name);
    }

};

sub initialize_from_new_process {

    my $userdir = LANraragi::Model::Config->get_userdir;

    $logger->info("Shinobu文件监视器启动.");
    $logger->info("内容文件夹为: $userdir.");

    update_filemap();
    $logger->info("初始扫描完成！ 将观监视器添加到内容文件夹以监视进一步的文件变动。");

    # 将观察器添加到内容目录
    my $contentwatcher = File::ChangeNotify->instantiate_watcher(
        directories     => [$userdir],
        filter          => qr/\.(?:zip|rar|7z|tar|tar\.gz|lzma|xz|cbz|cbr|cb7|cbt|pdf|epub)$/i,
        follow_symlinks => 1,
        exclude         => [ 'thumb', '.' ],                                                      #excluded subdirs
        depth       => 5,        #扫描档案目录时扫描的最大目录深度
    );

    my $class = ref($contentwatcher);
    $logger->debug("文件监视器类名为: $class");

    # Add watcher to tempfolder
    my $tempwatcher = File::ChangeNotify->instantiate_watcher( directories => [ get_temp() ] );

    # manual event loop
    $logger->info("全部初始化已经完成,文件监视器正在全力监测文件变动。");

    while (1) {

        # Check events on files
        for my $event ( $contentwatcher->new_events ) {
            $inotifysub->($event);
        }

        # Check the current temp folder size and clean it if necessary
        for my $event ( $tempwatcher->new_events ) {
            clean_temp_partial();
        }

        sleep 2;
    }
}

# Update the filemap. This acts as a masterlist of what's in the content directory.
# This computes IDs for all new archives and henceforth can get rather expensive!
sub update_filemap {

    $logger->info("正在扫描内容文件夹以查找更改...");
    my $redis = LANraragi::Model::Config->get_redis_config;

    # Clear hash
    my $dirname = LANraragi::Model::Config->get_userdir;
    my @files;

    # 在内容目录和子目录中获取所有文件。
    find(
        {   wanted => sub {
                return if -d $_;    #目录当场被排除在外
                return unless is_archive($_);
                push @files, $_;    #将文件推入数组
            },
            no_chdir    => 5,
            follow_fast => 1        #扫描档案目录时扫描的最大目录深度
        },
        $dirname
    );

    # Cross-check with filemap to get recorded files that aren't on the FS, and new files that aren't recorded.
    my @filemapfiles = $redis->exists("LRR_FILEMAP") ? $redis->hkeys("LRR_FILEMAP") : ();

    my %filemaphash = map { $_ => 1 } @filemapfiles;
    my %fshash      = map { $_ => 1 } @files;

    my @newfiles     = grep { !$filemaphash{$_} } @files;
    my @deletedfiles = grep { !$fshash{$_} } @filemapfiles;

    $logger->info( "找到 " . scalar @newfiles . " 个新文件." );
    $logger->info( scalar @deletedfiles . " 个文件在数据库里找到文件，但在文件系统上找不到文件。" );

    # Delete old files from filemap
    foreach my $deletedfile (@deletedfiles) {
        $logger->debug("正在从数据库中删除 $deletedfile");
        $redis->hdel( "LRR_FILEMAP", $deletedfile ) || $logger->warn("无法从数据库中删除以前的文件数据。");
    }

    $redis->quit();

    # Now that we have all new files, process them...with multithreading!
    my $numCpus = Sys::CpuAffinity::getNumCpus();
    my $pl      = Parallel::Loops->new($numCpus);

    $logger->debug("可用于处理的核心数量： $numCpus");
    my @sections = split_workload_by_cpu( $numCpus, @newfiles );

    # Eval the parallelized file crawl to avoid taking down the entire process in case one of the forked processes dies
    eval {
        $pl->foreach(
            \@sections,
            sub {
                my $redis = LANraragi::Model::Config->get_redis_config;
                foreach my $file (@$_) {

                    # Individual files are also eval'd so we can keep scanning
                    eval { add_to_filemap( $redis, $file ); };

                    if ($@) {
                        $logger->error("扫描 $file 文件时出现错误: $@");
                    }
                }
                $redis->quit();
            }
        );
    };

    if ($@) {
        $logger->error("扫描内容文件夹时出错： $@");
    }
}

sub add_to_filemap ( $redis_cfg, $file ) {

    my $redis_arc = LANraragi::Model::Config->get_redis;
    if ( is_archive($file) ) {

        $logger->debug("将 $file 添加到 Shinobu 数据库。");

        #Freshly created files might not be complete yet.
        #We have to wait before doing any form of calculation.
        while (1) {
            last unless -e $file;    # Sanity check to avoid sticking in this loop if the file disappears
            last if open( my $handle, '<', $file );
            $logger->debug("等待文件允许被打开");
            sleep(1);
        }

        # Wait for file to be more than 512 KBs or bailout after 5s and assume that file is smaller
        my $cnt = 0;
        while (1) {
            last if ( ( ( -s $file ) >= 512000 ) || $cnt >= 5 );
            $logger->debug("等待文件完全写入磁盘");
            sleep(1);
            $cnt++;
        }

        #Compute the ID of the archive and add it to the hash
        my $id = "";
        eval { $id = compute_id($file); };

        if ($@) {
            $logger->error("无法打开 $file 进行ID计算: $@");
            $logger->error("放弃将文件添加到数据库.");
            return;
        }

        $logger->debug("计算出的ID为: $id.");

        # If the id already exists on the server, throw a warning about duplicates
        if ( $redis_cfg->hexists( "LRR_FILEMAP", $file ) ) {

            my $filemap_id = $redis_cfg->hget( "LRR_FILEMAP", $file );

            $logger->debug("$file 文件已经存在于数据库中!");

            if ( $filemap_id ne $id ) {
                $logger->debug("$file 文件的ID与数据库中现有的ID不同! ($filemap_id)");
                $logger->info("$file 文件已被修改,已将其在数据库中的ID从 $filemap_id 修改为 $id.");

                LANraragi::Utils::Database::change_archive_id( $filemap_id, $id );

                # Don't forget to update the filemap, later operations will behave incorrectly otherwise
                $redis_cfg->hset( "LRR_FILEMAP", $file, $id );
            } else {
                $logger->debug(
                    "$file 文件的ID与数据库内的ID一致. 可能是重复的 inotify 事件触发? 为了防止出现其他意外情况现在开始清理缓存");
                invalidate_cache();
            }

            return;

        } else {
            $redis_cfg->hset( "LRR_FILEMAP", $file, $id );    # raw FS path so no encoding/decoding whatsoever
        }

        # Filename sanity check
        if ( $redis_arc->exists($id) ) {

            my $filecheck = $redis_arc->hget( $id, "file" );

            #Update the real file path and title if they differ from the saved one
            #This is meant to always track the current filename for the OS.
            unless ( $file eq $filecheck ) {
                $logger->debug("在数据库和文件系统之间检测到文件名差异！");
                $logger->debug("文件系统: $file");
                $logger->debug("数据库内: $filecheck");
                my ( $name, $path, $suffix ) = fileparse( $file, qr/\.[^.]*/ );
                $redis_arc->hset( $id, " 所属文件: ", $file );
                $redis_arc->hset( $id, " 所属名字: ", redis_encode($name) );
                $redis_arc->wait_all_responses;
                invalidate_cache();
            }

            # Set pagecount in case it's not already there
            unless ( $redis_arc->hget( $id, "pagecount" ) ) {
                $logger->debug("未计算 $id 的页数，立即执行！");
                LANraragi::Utils::Database::add_pagecount( $redis_arc, $id );
            }

        } else {

            # Add to Redis if not present beforehand
            add_new_file( $id, $file );
            invalidate_cache();
        }
    } else {
        $logger->debug("$file 未被识别为存档，正在跳过。");
    }
    $redis_arc->quit;
}

# Only handle new files. As per the ChangeNotify doc, it
# "handles the addition of new subdirectories by adding them to the watch list"
sub new_file_callback($name) {

    $logger->debug("检测到新文件: $name");
    unless ( -d $name ) {

        my $redis = LANraragi::Model::Config->get_redis_config;
        eval { add_to_filemap( $redis, $name ); };
        $redis->quit();

        if ($@) {
            $logger->error("处理新文件时出错: $@");
        }
    }
}

# Deleted files are simply dropped from the filemap.
# Deleted subdirectories trigger deleted events for every file deleted.
sub deleted_file_callback($name) {

    $logger->info("$name 已从内容文件夹中删除！");
    unless ( -d $name ) {

        my $redis = LANraragi::Model::Config->get_redis_config;

        # Prune file from filemap
        $redis->hdel( "LRR_FILEMAP", $name );

        eval { invalidate_cache(); };

        $redis->quit();
    }
}

sub add_new_file ( $id, $file ) {

    my $redis = LANraragi::Model::Config->get_redis;
    $logger->info("添加 ID 为 $id 的新文件 $file");

    eval {
        LANraragi::Utils::Database::add_archive_to_redis( $id, $file, $redis );
        LANraragi::Utils::Database::add_timestamp_tag( $redis, $id );
        LANraragi::Utils::Database::add_pagecount( $redis, $id );

        #AutoTagging using enabled plugins goes here!
        LANraragi::Model::Plugins::exec_enabled_plugins_on_file($id);
    };

    if ($@) {
        $logger->error("添加文件时出错： $@");
    }
    $redis->quit;
}

__PACKAGE__->initialize_from_new_process unless caller;

1;
