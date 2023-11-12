#!/usr/bin/env perl

use strict;
use warnings;

use open ':std', ':encoding(UTF-8)';
use Cwd;
use Config;
use utf8;
use File::Copy;
use feature qw(say);
use File::Path qw(make_path);

#Vendor dependencies
my @vendor_css = (
    "/blueimp-file-upload/css/jquery.fileupload.css",      "/\@fortawesome/fontawesome-free/css/all.min.css",
    "/jqcloud2/dist/jqcloud.min.css",                      "/react-toastify/dist/ReactToastify.min.css",
    "/jquery-contextmenu/dist/jquery.contextMenu.min.css", "/tippy.js/dist/tippy.css",
    "/allcollapsible/dist/css/allcollapsible.min.css",     "/awesomplete/awesomplete.css",
    "/\@jcubic/tagger/tagger.css",                         "/swiper/swiper-bundle.min.css",
    "/sweetalert2/dist/sweetalert2.min.css",
);

my @vendor_js = (
    "/blueimp-file-upload/js/jquery.fileupload.js",       "/blueimp-file-upload/js/vendor/jquery.ui.widget.js",
    "/datatables.net/js/jquery.dataTables.min.js",        "/jqcloud2/dist/jqcloud.min.js",
    "/jquery/dist/jquery.min.js",                         "/react-toastify/dist/react-toastify.umd.js",
    "/jquery-contextmenu/dist/jquery.ui.position.min.js", "/jquery-contextmenu/dist/jquery.contextMenu.min.js",
    "/tippy.js/dist/tippy-bundle.umd.min.js",             "/\@popperjs/core/dist/umd/popper.min.js",
    "/allcollapsible/dist/js/allcollapsible.min.js",      "/awesomplete/awesomplete.min.js",
    "/\@jcubic/tagger/tagger.js",                         "/marked/marked.min.js",
    "/swiper/swiper-bundle.min.js",                       "/preact/dist/preact.umd.js",
    "/clsx/dist/clsx.min.js",                             "/preact/compat/dist/compat.umd.js",
    "/preact/hooks/dist/hooks.umd.js",                    "/sweetalert2/dist/sweetalert2.min.js",
    "/fscreen/dist/fscreen.esm.js"
);

my @vendor_woff = (
    "/\@fortawesome/fontawesome-free/webfonts/fa-solid-900.woff2",
    "/\@fortawesome/fontawesome-free/webfonts/fa-regular-400.woff2",
    "/geist/dist/fonts/geist-sans/Geist-Regular.woff2",
    "/geist/dist/fonts/geist-sans/Geist-SemiBold.woff2",
    "/inter-ui/Inter (web)/Inter-Regular.woff",
    "/inter-ui/Inter (web)/Inter-Bold.woff",
);

say("⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⣠⣴⣶⣿⠿⠟⠛⠓⠒⠤");
say("⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⣠⣾⣿⡟⠋");
say("⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⢰⣿⣿⠋");
say("⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⢀⣿⣿⠇⡀");
say("⢀⢀⢀⢀⢀⢀⢀⢀⢀⣀⣤⡆⢿⣿⢀⢿⣷⣦⣄⣀");
say("⢀⢀⢀⢀⢀⢀⢀⣶⣿⠿⠛⠁⠈⢻⡄⢀⠈⠙⠻⢿⣿⣆");
say("⢀⢀⢀⢀⢀⢀⢸⣿⣿⣶⣤⣀⢀⢀⢀⢀⢀⣀⣤⣶⣿⣿");
say("⢀⢀⢀⢀⢀⢀⢸⣿⣿⣿⣿⣿⣿⣶⣤⣶⣿⠿⠛⠉⣿⣿");
say("⢀⢀⢀⢀⢀⢀⢸⣿⣿⣿⣿⣿⣿⣿⣿⠉⢀⢀⢀⢀⣿⣿");
say("⢀⢀⢀⢀⣀⣤⣾⣿⣿⣿⣿⣿⣿⣿⣿⢀⢀⢀⣠⣴⣿⣿⣦⣄⡀");
say("⢀⣤⣶⣿⠿⠟⠉⢀⠉⠛⠿⣿⣿⣿⣿⣴⣾⡿⠿⠋⠁⠈⠙⠻⢿⣷⣦⣄");
say("⣿⣿⣯⣅⢀⢀⢀⢀⢀⢀⢀⣀⣭⣿⣿⣿⣍⡀⢀⢀⢀⢀⢀⢀⢀⣨⣿⣿⡇");
say("⣿⣿⣿⣿⣿⣶⣤⣀⣤⣶⣿⡿⠟⢹⣿⣿⣿⣿⣷⣦⣄⣠⣴⣾⡿⠿⠋⣿⡇");
say("⣿⣿⣿⣿⣿⣿⣿⣿⡟⠋⠁⢀⢀⢸⣿⣿⣿⣿⣿⣿⣿⣿⠛⠉⢀⢀⢀⣿⡇");
say("⣿⣿⣿⣿⣿⣿⣿⣿⡇⢀⢀⢀⢀⣸⣿⣿⣿⣿⣿⣿⣿⣿⢀⢀⢀⢀⢀⣿⡇");
say("⠙⢿⣿⣿⣿⣿⣿⣿⡇⢀⣠⣴⣿⡿⠿⣿⣿⣿⣿⣿⣿⣿⢀⣀⣤⣾⣿⠟⠃");
say("⢀⢀⠈⠙⠿⣿⣿⣿⣷⣿⠿⠛⠁⢀⢀⢀⠉⠻⢿⣿⣿⣿⣾⡿⠟⠉");
say("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
say("~~~~~LANraragi  安装程序~~~~~");
say("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");

unless ( @ARGV > 0 ) {
    say("执行：npm run lanraragi-installer [模式]");
    say("--------------------------");
    say("可用模式有：");
    say("* install-front: 安装/更新依赖项。");
    say("* install-back : 安装/更新 Perl 依赖项。");
    say("* install-full : 安装/更新所有依赖项。");
    say("");
    say("如果是第一次安装依赖，请使用 install-full。");
    exit;
}

my $front = $ARGV[0] eq "install-front";
my $back  = $ARGV[0] eq "install-back";
my $full  = $ARGV[0] eq "install-full";

say( "工作目录: " . getcwd );
say("");

# Provide cpanm with the correct module installation dir when using Homebrew
my $cpanopt = "";
if ( $ENV{HOMEBREW_FORMULA_PREFIX} ) {
    $cpanopt = " -l " . $ENV{HOMEBREW_FORMULA_PREFIX} . "/libexec";
}

#Load IPC::Cmd
install_package( "IPC::Cmd",         $cpanopt );
install_package( "Config::AutoConf", $cpanopt );
IPC::Cmd->import('can_run');
require Config::AutoConf;

say("\r\n现在开始检查所有软件依赖是否满足运行 LRR 。 \r\n");

#Check for Redis
say("检查Redis...");
can_run('redis-server')
  or die '未找到Redis服务器! 请在继续前安装redis-server.';
say("完成!");

#Check for GhostScript
say("检查GhostScript...");
can_run('gs')
  or warn '未找到! PDF PDF 支持将无法正常工作。 请安装"gs"工具。';
say("完成!");

#Check for libarchive
say("检查libarchive...");
Config::AutoConf->new()->check_header("archive.h")
  or die '未找到! 请安装libarchive并保证headers能被引用。';
say("完成!");

#Check for PerlMagick
say("检查ImageMagick/PerlMagick...");
my $imgk;

eval {
    require Image::Magick;
    $imgk = Image::Magick->QuantumDepth;
};

if ($@) {
    say("未找到");
    say("请安装ImageMagick否则缩略图将无法被生成。");
    say("有关说明访问: https://www.imagemagick.org/script/perl-magick.php 获取。");
    say("ImageMagick检测命令返回的内容: $imgk -- $@");
} else {
    say( "色彩深度: " . $imgk );
    say("完成!");
}

#Build & Install CPAN Dependencies
if ( $back || $full ) {
    say("\r\n安装 Perl 模块......    这可能需要一些时间。\r\n");

    if ( $Config{"osname"} ne "darwin" ) {
        say("正在为非 macOS 系统安装 Linux::Inotify2...（如果软件包已经存在，这将不会执行任何操作）");

        install_package( "Linux::Inotify2", $cpanopt );
    }

    if ( system( "cpanm --installdeps ./tools/. --notest" . $cpanopt ) != 0 ) {
        die "安装Perl模块时出现问题 - 救助。";
    }
}

#Clientside Dependencies with Provisioning
if ( $front || $full ) {

    say("\r\n从远程服务器获取依赖...\r\n");

    if ( system("npm install") != 0 ) {
        die "在获取 node 模块时出现了问题 - 退出。";
    }

    say("\r\n正在配置...\r\n");

    #Load File::Copy
    install_package( "File::Copy", $cpanopt );
    File::Copy->import("copy");

    make_path getcwd . "/public/css/vendor";
    make_path getcwd . "/public/css/webfonts";
    make_path getcwd . "/public/js/vendor";

    for my $css (@vendor_css) {
        cp_node_module( $css, "/public/css/vendor/" );
    }

    #Rename the fontawesome css to something a bit more explanatory
    copy( getcwd . "/public/css/vendor/all.min.css", getcwd . "/public/css/vendor/fontawesome-all.min.css" );

    for my $js (@vendor_js) {
        cp_node_module( $js, "/public/js/vendor/" );
    }

    for my $woff (@vendor_woff) {
        cp_node_module( $woff, "/public/css/webfonts/" );
    }

}

#install Customize Plugin ETagCN
cp_customize_plugin("/customize/ETagCN/ETagCN.pm","/lib/LANraragi/Plugin/Metadata/ETagCN.pm","ETagCN");

#install Customize Plugin ETagConverter
cp_customize_plugin("/customize/ETagConverter/ETagConverter.pm","/lib/LANraragi/Plugin/Scripts/ETagConverter.pm","ETagConverter");



#Done!
say("\r\n一切就绪！您可以通过输入以下命令来启动 LANraragi: \r\n");
say("   ╭─────────────────────────────────────╮");
say("   │                                     │");
say("   │              npm start              │");
say("   │                                     │");
say("   ╰─────────────────────────────────────╯");

sub cp_node_module {

    my ( $item, $newpath ) = @_;

    my $nodename = getcwd . "/node_modules" . $item;
    $item =~ /([^\/]+$)/;
    my $newname     = getcwd . $newpath . $&;
    my $nodemapname = $nodename . ".map";
    my $newmapname  = $newname . ".map";

    say("\r\n正在复制 $nodename \r\n to $newname");
    copy( $nodename, $newname ) or die "执行复制操作失败: $!";

    my $mapresult = copy( $nodemapname, $newmapname ) and say("成功复制了 sourcemap 文件。\r\n");

}

sub install_package {

    my $package = $_[0];
    my $cpanopt = $_[1];

    ## no critic
    eval "require $package";    #Run-time evals are needed here to check if the package has been properly installed.
    ## use critic

    if ($@) {
        say("$package 没有安装！正在尝试使用 cpanm 安装 $cpanopt");
        system("cpanm $package $cpanopt");
    } else {
        say("$package 包已安装，继续...");
    }
}

sub cp_customize_plugin {

    my ( $plugin_file, $plugin_path ,$plugin_name) = @_;
    $plugin_file = getcwd . $plugin_file;
    $plugin_path = getcwd . $plugin_path;

    say("\r\n安装插件: $plugin_name \r\n");
    say("\r\n正在复制 $plugin_file \r\n to $plugin_path");
    copy($plugin_file,$plugin_path) or die "将 $plugin_file 复制到 $plugin_path 失败\n";

}