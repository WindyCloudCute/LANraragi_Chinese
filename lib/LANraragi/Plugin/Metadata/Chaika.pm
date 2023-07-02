package LANraragi::Plugin::Metadata::Chaika;

use strict;
use warnings;
use utf8;
use URI::Escape;
use Mojo::UserAgent;
use Mojo::DOM;
use LANraragi::Utils::Logging qw(get_plugin_logger);

my $chaika_url = "https://panda.chaika.moe";

#Meta-information about your plugin.
sub plugin_info {

    return (
        #Standard metadata
        name        => "Chaika.moe",
        type        => "metadata",
        namespace   => "trabant",
        author      => "Difegue",
        version     => "2.3",
        description => "在 chaika.moe 中搜索与您的档案匹配的标签。 这将首先尝试使用缩略图,然后回退到默认文本搜索.",
        icon =>
          "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAACXBIWXMAAAsTAAALEwEAmpwYAAAA\nB3RJTUUH4wYCFQocjU4r+QAAAB1pVFh0Q29tbWVudAAAAAAAQ3JlYXRlZCB3aXRoIEdJTVBkLmUH\nAAAEZElEQVQ4y42T3WtTdxzGn/M7J+fk5SRpTk7TxMZkXU84tTbVNrUT3YxO7HA4pdtQZDe7cgx2\ns8vBRvEPsOwFYTDYGJUpbDI2wV04cGXCGFLonIu1L2ptmtrmxeb1JDkvv121ZKVze66f74eH7/f5\nMmjRwMCAwrt4/9KDpflMJpPHvyiR2DPcJklJ3TRDDa0xk36cvrm8vDwHAAwAqKrqjjwXecPG205w\nHBuqa9rk77/d/qJYLD7cCht5deQIIczbgiAEKLVAKXWUiqVV06Tf35q8dYVJJBJem2A7Kwi2nQzD\nZig1CG93+PO5/KN6tf5NKpVqbsBUVVVFUUxwHJc1TXNBoxojS7IbhrnLMMx9pVJlBqFQKBKPxwcB\nkJYgjKIo3QCE1nSKoghbfJuKRqN2RVXexMaQzWaLezyeEUEQDjscjk78PxFFUYRkMsltJgGA3t7e\nyMLCwie6rr8iCILVbDbvMgwzYRjGxe0o4XC4s1AoHPP5fMP5/NNOyzLKAO6Ew+HrDADBbre/Ryk9\nnzx81FXJNlEpVpF+OqtpWu2MpmnXWmH9/f2umZmZi4cOHXnLbILLzOchhz1YerJAs9m1GwRAg2GY\nh7GYah488BJYzYW+2BD61AFBlmX/1nSNRqN9//792ujoaIPVRMjOKHoie3DytVGmp2fXCAEAjuMm\nu7u7Umosho6gjL/u/QHeEgvJZHJ2K/D+/fuL4+PjXyvPd5ldkShy1UXcmb4DnjgQj/fd5gDA6/XS\nYCAwTwh9oT3QzrS1+VDVi+vd3Tsy26yQVoFF3dAXJVmK96p9EJ0iLNOwKKU3CQCk0+lSOpP5WLDz\nF9Q9kZqyO0SloOs6gMfbHSU5NLRiUOuax2/HyZPHEOsLw2SbP83eu/fLxrkNp9P554XxCzVa16MC\n7+BPnTk9cfmH74KJE8nmga7Xy5JkZ8VKifGIHpoBb1VX8hNTd3/t/7lQ3OeXfFPvf/jBRw8ezD/a\n7M/aWq91cGgnJaZ2VcgSdnV1XRNNd3vAoBVVYusmnEQS65hfgSG6c+zy3Kre7nF/KrukcMW0Zg8O\nD08DoJutDxxOEb5IPUymwrq8ft1gLKfkFojkkRxemERCAQUACPFWRazYLJcrFGwQhyufbQQ7rFpy\nLMkCwGZC34qPIuwp+XPOjBFwazQ/txrdFS2GGS/Xuj+pUKLGk1Kjvlded3s72lyGW+PLbGVcmrAA\ngN0wTk1NWYODg9XOKltGtpazi5GigzroUnHN5nUHG1ylRsG7rDXHmnEpu4CeEtEKkqNc6QqlLc/M\n8uT5lLH5eq0aGxsju1O7GQB498a5s/0x9dRALPaQEDZnYwnhWJtMCCNrjeb0UP34Z6e/PW22zjPP\n+vwXBwfPvbw38XnXjk7GsiwKAIQQhjAMMrlsam45d+zLH6/8o6vkWcBcrXbVKQhf6bpucCwLjmUB\nSmmhXC419eblrbD/TAgAkUjE987xE0c7ZDmk66ajUCnq+cL63fErl25s5/8baQPaWLhx6goAAAAA\nSUVORK5CYII=",
        parameters  => [
            { type => "bool", desc => "保存存档标题" },
            { type => "bool", desc => "添加以下标签(如果可用)：下载URL,Gallery ID,类别,时间戳" },
            { type => "bool", desc => "将没有名称空间的标签添加到“另一个：”名称空间,反映了E-H的命名空间的行为" },
            { type => "string", desc => "将自定义的“源：”标签添加到您的存档中。示例：chaika。如果空白,不会添加标签" }
        ],
        oneshot_arg => "Chaika Gallery或存档URL(将在您的档案中附加匹配标签)"
    );

}

#Mandatory function to be implemented by your plugin
sub get_tags {

    shift;
    my $lrr_info = shift;    # Global info hash
    my ( $savetitle, $addextra, $addother, $addsource ) = @_;    # Plugin parameters

    my $logger   = get_plugin_logger();
    my $newtags  = "";
    my $newtitle = "";

    # Parse the given link to see if we can extract type and ID
    my $oneshotarg = $lrr_info->{oneshot_param};
    if ( $oneshotarg =~ /https?:\/\/panda\.chaika\.moe\/(gallery|archive)\/([0-9]*)\/?.*/ ) {
        ( $newtags, $newtitle ) = tags_from_chaika_id( $1, $2, $addextra, $addother, $addsource );
    } else {

        # Try SHA-1 reverse search first
        $logger->info("Using thumbnail hash " . $lrr_info->{thumbnail_hash});
        ( $newtags, $newtitle ) = tags_from_sha1( $lrr_info->{thumbnail_hash}, $addextra, $addother, $addsource );

        # Try text search if it fails
        if ( $newtags eq "" ) {
            $logger->info("No results, falling back to text search.");
            ( $newtags, $newtitle ) = search_for_archive( $lrr_info->{archive_title}, $lrr_info->{existing_tags}, $addextra, $addother, $addsource );
        }
    }

    if ( $newtags eq "" ) {
        $logger->info("No matching Chaika Archive Found!");
        return ( error => "No matching Chaika Archive Found!" );
    } else {
        $logger->info("Sending the following tags to LRR: $newtags");
        #Return a hash containing the new metadata
        if ( $savetitle && $newtags ne "" ) { return ( tags => $newtags, title => $newtitle ); }
        else                                { return ( tags => $newtags ); }
    }

}

######
## Chaika Specific Methods
######

# search_for_archive
# Uses chaika's html search to find a matching archive ID
sub search_for_archive {

    my $logger = get_plugin_logger();
    my ( $title, $tags, $addextra, $addother, $addsource ) = @_;

    #Auto-lowercase the title for better results
    $title = lc($title);

    #Strip away hyphens and apostrophes as they apparently break search
    $title =~ s/-|'/ /g;

    my $URL = "$chaika_url/jsearch/?gsp&title=" . uri_escape_utf8($title) . "&tags=";

    #Append language:english tag, if it exists.
    #Chaika only has english or japanese so I aint gonna bother more than this
    if ( $tags =~ /.*language:\s?english,*.*/gi ) {
        $URL = $URL . uri_escape_utf8("language:english") . "+";
    }

    $logger->debug("Calling $URL");
    my $ua  = Mojo::UserAgent->new;
    my $res = $ua->get($URL)->result;

    my $textrep = $res->body;
    $logger->debug("Chaika API returned this JSON: $textrep");

    my ( $chaitags, $chaititle ) = parse_chaika_json( $res->json->{"galleries"}->[0], $addextra, $addother, $addsource );

    return ( $chaitags, $chaititle );
}

# Uses the jsearch API to get the best json for a file.
sub tags_from_chaika_id {

    my ( $type, $ID, $addextra, $addother, $addsource ) = @_;

    my $json = get_json_from_chaika( $type, $ID );
    return parse_chaika_json( $json, $addextra, $addother, $addsource );
}

# tags_from_sha1
# Uses chaika's SHA-1 search with the first page hash we have.
sub tags_from_sha1 {

    my ( $sha1, $addextra, $addother, $addsource ) = @_;

    my $logger = get_plugin_logger();

    # The jsearch API immediately returns a JSON.
    # Said JSON is an array containing multiple archive objects.
    # We just take the first one.
    my $json_by_sha1 = get_json_from_chaika( 'sha1', $sha1 );
    return parse_chaika_json( $json_by_sha1->[0], $addextra, $addother, $addsource );
}

# Calls chaika's API
sub get_json_from_chaika {

    my ( $type, $value ) = @_;

    my $logger = get_plugin_logger();
    my $URL    = "$chaika_url/jsearch/?$type=$value";
    my $ua     = Mojo::UserAgent->new;
    my $res    = $ua->get($URL)->result;

    if ($res->is_error) {
        return;
    }
    my $textrep = $res->body;
    $logger->debug("Chaika API returned this JSON: $textrep");

    return $res->json;
}

# Parses the JSON obtained from the Chaika API to get the tags.
sub parse_chaika_json {

    my ( $json, $addextra, $addother, $addsource ) = @_;

    my $tags = $json->{"tags"} || ();
    foreach my $tag (@$tags) {
        #Replace underscores with spaces
        $tag =~ s/_/ /g;
        
        #Add 'other' namespace if none
        if ($addother && index($tag, ":") == -1) {
            $tag = "other:" . $tag;
        }
    }

    my $category = lc $json->{"category"};
    my $download = $json->{"download"} ? $json->{"download"} : $json->{"archives"}->[0]->{"link"};
    my $gallery = $json->{"gallery"} ? $json->{"gallery"} : $json->{"id"};
    my $timestamp = $json->{"posted"};
    if ($tags && $addextra) {
        if ($category ne "") {
            push(@$tags, "category:" . $category);
        }
        if ($download ne "") {
            push(@$tags, "download:" . $download);
        }
        if ($gallery ne "") {
            push(@$tags, "gallery:" . $gallery);
        }
        if ($timestamp ne "") {
            push(@$tags, "timestamp:" . $timestamp);
        }
    }

    if ($gallery && $gallery ne "") {
        # add custom source, but only if having found gallery
        if ($addsource && $addsource ne "") {
            push(@$tags, "source:" . $addsource);
        }
        return ( join( ', ', @$tags ), $json->{"title"} );
    } else {
        return "";
    }
}

1;
