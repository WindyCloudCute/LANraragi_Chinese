package LANraragi::Model::Upload;

use strict;
use warnings;
use utf8;
use Redis;
use URI::Escape;
use File::Basename;
use File::Temp qw(tempdir);
use File::Find qw(find);
use File::Copy qw(move);

use LANraragi::Utils::Database qw(invalidate_cache compute_id);
use LANraragi::Utils::Logging qw(get_logger);
use LANraragi::Utils::Database qw(redis_encode);
use LANraragi::Utils::Generic qw(is_archive get_bytelength);
use LANraragi::Utils::String qw(trim trim_CRLF trim_url);

use LANraragi::Model::Config;
use LANraragi::Model::Plugins;
use LANraragi::Model::Category;

# Handle files uploaded by the user, or downloaded from remote endpoints.

# Process a file.
# First argument is the filepath, preferably in a temp directory,
# as we'll copy it to the content folder and delete the original at the end.
#
# The file will be added to a category, if its ID is specified.
# You can also specify tags to add to the metadata for the processed file before autoplugin is ran. (if it's enabled)
#
# Returns a status value, the ID and title of the file, and a status message.
sub handle_incoming_file {

    my ( $tempfile, $catid, $tags )   = @_;
    my ( $filename, $dirs,  $suffix ) = fileparse( $tempfile, qr/\.[^.]*/ );
    $filename = $filename . $suffix;
    my $logger = get_logger( "文件上传/下载", "lanraragi" );

    # Check if file is an archive
    unless ( is_archive($filename) ) {
        return ( 0, "deadbeef", $filename, "不支持的文件扩展名 ($filename)" );
    }

    # Compute an ID here
    my $id = compute_id($tempfile);
    $logger->debug("ID of uploaded file is $id");

    # Future home of the file
    my $userdir     = LANraragi::Model::Config->get_userdir;
    my $output_file = $userdir . '/' . $filename;

    #Check if the ID is already in the database, and
    #that the file it references still exists on the filesystem
    my $redis        = LANraragi::Model::Config->get_redis;
    my $redis_search = LANraragi::Model::Config->get_redis_search;
    my $replace_dupe = LANraragi::Model::Config->get_replacedupe;
    my $isdupe       = $redis->exists($id) && -e $redis->hget( $id, "file" );

    # Stop here if file is a dupe and replacement is turned off.
    if ( ( -e $output_file || $isdupe ) && !$replace_dupe ) {

        # Trash temporary file
        unlink $tempfile;

        # The file already exists
        my $suffix = " 启用在配置中替换重复的存档以替换旧的档案。";
        my $msg =
          $isdupe
          ? "该文件已存在于库中。" . $suffix
          : "库中存在具有相同名称的文件。" . $suffix;

        return ( 0, $id, $filename, $msg );
    }

    # If we are replacing an existing one, just remove the old one first.
    if ($replace_dupe) {
        $logger->debug("更换之前删除存档 $id。");
        LANraragi::Utils::Database::delete_archive($id);
    }

    # Add the file to the database ourselves so Shinobu doesn't do it
    # This allows autoplugin to be ran ASAP.
    my $name = LANraragi::Utils::Database::add_archive_to_redis( $id, $output_file, $redis );

    # If additional tags were given to the sub, add them now.
    if ($tags) {
        $redis->hset( $id, "tags", redis_encode($tags) );

        # Check for a source: tag, and if it exists amend the urlmap by hand.
        # This is faster than queueing a full recalculation job.
        my @tags = split( /,\s?/, $tags );

        foreach my $t (@tags) {
            $t = trim($t);
            $t = trim_CRLF($t);

            # If the tag is a source: tag, add it to the URL index
            if ( $t =~ /source:(.*)/i ) {
                my $url = $1;
                $logger->debug("添加 $url 作为 $id 的 URL");
                trim_url($url);
                $logger->debug("已修剪：$url");

                # No need to encode the value, as URLs are already encoded by design
                $redis_search->hset( "LRR_URLMAP", $url, $id );
            }
        }
    }

    # Move the file to the content folder.
    # Move to a .upload first in case copy to the content folder takes a while...
    move( $tempfile, $output_file . ".upload" );

    # Then rename inside the content folder itself to proc Shinobu.
    move( $output_file . ".upload", $output_file );

    unless ( -e $output_file ) {
        return ( 0, $id, $name, "该文件无法移至您的内容文件夹！" );
    }

    # Now that the file has been copied, we can add the timestamp tag and calculate pagecount.
    # (The file being physically present is necessary in case last modified time is used)
    LANraragi::Utils::Database::add_timestamp_tag( $redis, $id );
    LANraragi::Utils::Database::add_pagecount( $redis, $id );
    LANraragi::Utils::Database::add_arcsize( $redis, $id );
    $redis->quit();
    $redis_search->quit();

    $logger->debug("在新上传的文件 $id 上运行自动插件...");

    my ( $succ, $fail, $addedtags, $newtitle ) = LANraragi::Model::Plugins::exec_enabled_plugins_on_file($id);
    my $successmsg = "$succ 插件使用成功，$fail 插件失败，$addedtags 标签已添加。 ";

    if ( $newtitle ne "" ) {
        $name = $newtitle;
    }

    if ($catid) {
        $logger->debug("将上传的文件添加到类别 $catid");

        my ( $catsucc, $caterr ) = LANraragi::Model::Category::add_to_category( $catid, $id );
        if ($catsucc) {
            my %category = LANraragi::Model::Category::get_category($catid);
            my $catname  = $category{name};
            $successmsg .= "添加到类别“$catname”！";
        } else {
            $successmsg .= "无法添加到类别：$caterr";
        }
    }

    # Invalidate search cache ourselves, Shinobu won't do it since the file is already in the database
    invalidate_cache();

    return ( 1, $id, $name, $successmsg );
}

# Download the given URL, using the given Mojo::UserAgent object.
# This downloads the URL to a temporaryfolder and returns the full path to the downloaded file.
sub download_url {

    my ( $url, $ua ) = @_;

    my $logger = get_logger( "文件上传/下载", "lanraragi" );

    # Download to a temp folder
    die "Not a proper URL" unless $url;
    $logger->info("下载 URL $url...这将需要一些时间。");

    my $tempdir = tempdir();

    # Download the URL, with 5 maximum redirects and unlimited response size.
    my $tx           = $ua->max_response_size(0)->max_redirects(5)->get($url);
    my $content_disp = $tx->result->headers->content_disposition;
    my $filename     = "Not_an_archive";                                         #placeholder;

    $logger->debug("内容 Header: $content_disp");
    if ( $content_disp =~ /.*filename=\"(.*)\".*/gim ) {
        $filename = $1;
    } elsif ( $content_disp =~ /.*filename\*=UTF-8''(.*)/gim ) {

        # This is an UTF8 filename as per rfc5987.
        # URL-decode to get the full filename.
        $filename = uri_unescape($1);

    } elsif ( $url =~ /([^\/]+)\/?$/gm ) {

        # Fallback to the last element of the URL as the filename.
        $filename = $1;
    }

    $logger->debug("文件名: $filename");

    # remove invalid Windows chars
    $filename =~ s@[\\/:"*?<>|]+@@g;

    my ( $fn, $path, $ext ) = fileparse( $filename, qr/\.[^.]*/ );
    my $byte_limit = LANraragi::Model::Config->enable_cryptofs ? 143 : 255;

    # don't allow the main filename to exceed the given byte limit
    # for extension and .upload prefix used by `handle_incoming_file`
    $filename = $fn;
    while ( get_bytelength( $filename . $ext . ".upload" ) > $byte_limit ) {
        $filename = substr( $filename, 0, -1 );
    }
    $filename = $filename . $ext;
    $logger->debug("处理后的文件名: $filename");
    $tx->result->save_to("$tempdir\/$filename");

    # Update $tempfile to the exact reference created by the host filesystem
    # This is done by finding the first (and only) file in $tempdir.
    my $tempfile = "";
    find(
        sub {
            return if -d $_;
            $tempfile = $File::Find::name;
            $filename = $_;
        },
        $tempdir
    );

    return "$tempdir\/$filename";
}

1;
