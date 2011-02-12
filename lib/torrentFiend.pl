# The original version, written in PERL #
##
# TorrentFiend by Levi Hackwith is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike
# 3.0 United States License.
# For proper attribution, just put a link in your sourcecode or on your site back to http://www.levihackwith.com
# This software is offered 'as-is' and is for educational purposes only. If you do something stupid with it, don't come
# running to me.
##
use strict;
use XML::Parser;
use LWP::UserAgent;
use HTTP::Status;
use DBI;
my $dbh = DBI->connect("dbi:SQLite:dbname=fiend.db", "", "", { RaiseError => 1, AutoCommit => 1 });
my $userAgent = new LWP::UserAgent; # Create new user agent
$userAgent->agent("Mozilla/4.0"); # Spoof our user agent as Mozilla
$userAgent->timeout(20); # Set timeout limit for request
my $currentTag = ""; # Stores what tag is currently being parsed
my $torrentUrl = ""; # Stores the data found in any  node
my $isDownloaded = 0; # 1 or zero that states whether or not we've downloaded a particular episode
my $shows = $dbh->selectall_arrayref("SELECT id, name, current_season, last_episode FROM shows ORDER BY name");
my $id = 0;
my $name = "";
my $season = 0;
my $last_episode = 0;
foreach my $show (@$shows) {
    $isDownloaded = 0;
    ($id, $name, $season, $last_episode) = (@$show);
    $season = sprintf("%02d", $season); # Append a zero to the season (e.g. 6 becomes 06)
    $last_episode = sprintf("%02d", ($last_episode + 1)); # Append a zero to the last episode (e.g. 6 becomes 06) and increment it by one
    print("Checking $name S" . $season . "E" . "$last_episode \n");
    my $request = new HTTP::Request(GET => "http://btjunkie.org/rss.xml?query=$name S" . $season . "E" . $last_episode . "&o=52"); # Retrieve the torrent feed
    my $rssFeed = $userAgent->request($request);  # Store the feed in a variable for later access
    if($rssFeed->is_success) { # We retrieved the feed
        my $parser = new XML::Parser(); # Make a new instance of XML::Parser
        $parser->setHandlers # Set the functions that will be called when the parser encounters different kinds of data within the XML file.
        (
            Start => \&startHandler, # Handles start tags (e.g. )
            End   => \&endHandler, # Handles end tags (e.g.
            Char  => \&DataHandler # Handles data inside of start and end tags
        );
        $parser->parsestring($rssFeed->content); # Parse the feed
    }
}

#
# Called every time XML::Parser encounters a start tag
# @param: $parseInstance {object} | Instance of the XML::Parser. Passed automatically when feed is parsed.
# @param: $element {string} | The name of the XML element being parsed (e.g. "title"). Passed automatically when feed is parsed.
# @attributes {array} | An array of all of the attributes of $element
# @returns: void
#
sub startHandler {
    my($parseInstance, $element, %attributes) = @_;
    $currentTag = $element;
}
#
# Called every time XML::Parser encounters anything that is not a start or end tag (i.e, all the data in between tags)
# @param: $parseInstance {object} | Instance of the XML::Parser. Passed automatically when feed is parsed.
# @param: $element {string} | The name of the XML element being parsed (e.g. "title"). Passed automatically when feed is parsed.
# @attributes {array} | An array of all of the attributes of $element
# @returns: void
#
sub DataHandler {
    my($parseInstance, $element, %attributes) = @_;
    if($currentTag eq "link" && $element ne "\n") {
        $torrentUrl = $element;
    }
}
#
# Called every time XML::Parser encounters an end tag
# @param: $parseInstance {object} | Instance of the XML::Parser. Passed automatically when feed is parsed.
# @param: $element {string} | The name of the XML element being parsed (e.g. "title"). Passed automatically when feed is parsed.
# @attributes {array} | An array of all of the attributes of $element
# @returns: void
#
sub endHandler {
    my($parseInstance, $element, %attributes) = @_;
    if($element eq "item" && $isDownloaded == 0) { # We just finished parsing an  element so let's attempt to download a torrent
        print("DOWNLOADING: $torrentUrl" . "/download.torrent \n");
        system("echo.|lwp-download " . $torrentUrl . "/download.torrent"); # We echo the "return " key into the command to force it to skip any file-overwite prompts
        if(unlink("download.torrent.html")) { # We tried to download a 'locked' torrent
            $isDownloaded = 0; # Forces program to download next torrent on list from current show
        }
        else {
            $isDownloaded = 1;
            $dbh->do("UPDATE shows SET last_episode = '$last_episode' WHERE id = '$id'"); # Update DB with new show information
        }
    }
}