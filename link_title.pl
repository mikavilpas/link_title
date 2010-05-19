# Link title script! :)
# :DDDDDDDDDDDDDD
#
# based on http://paste.lisp.org/display/58040
# Modded by sp3ctum
#
# What this script does:
# 
# Someone sends a link, say http://www.youtube.com
# This script gets a piece of that page and looks for a <title> tag
# and prints the title before printing the link. That way you have
# an idea what the page contains before opening it.
# - displays the last url of multiple redirects
# TODO laita linkki esimerkkikuvaan
# Also, you see if the link has already been sent to you by someone else.
# The links are colored differently depending on whether or not the link is
# interesting, typically an image or swf. It's also possible to have
# the links go to a window just for them, which you can optionally log
# (and search!) via irssi.
# TODO: more features, or should they be in the example?
#
# TODO munasti dokumentointia, tää on sairaan sekavaa
# TODO tarkistus sille, onko file-ohjelmaa olemassa ja mahdollisuus
# toimia ilman sitä

use Irssi;
use Irssi::Irc;
use LWP::UserAgent;
use HTML::Entities;
use IPC::Open2; # for determining file type with the "file" command

use warnings;
use strict;

# different color formats or headers for different types, see 
# http://irssi.org/documentation/formats for their meanings
# note! don't use bolded colors in case you want to
# have an unbolded title (old link)
my %colors = (
    # title age: new ones get bolded, old ones don't
    new_title      => "%9", # bold
    old_title      => "",
    # title types: 
    # different color for links with titles and vice versa 
    has_title      => "%g", # green
    has_no_title   => "%r", # red
    interesting    => "%U", # underlined
    # color of the received IRC message with the link
    data_color     => "%K", # dark grey
    # if the link is redirected to a new place,
    # the uri of the new place is printed with this color
    redirect_color => "%y"  # yellow
 );
             
# these headers are put at the very beginning of the title
# format: regexp => [header, text to delete from title]
my %site_headers = (
    "http://www.youtube\." => ["%9You%1Tube%n ", "YouTube "],
    "https?://www.facebook\." => ["%4%Wfacebook%n ", " . Facebook\$"],
    "http://..\.wikipedia\.org" => ["%7%kWikipedia%n ", "( - Wikipedia,.*| – Wikipedia.*)\$"],
    "http://.*upload.wikimedia.org/" => ["%7%kWikimedia%n ", "( - Wikipedia,.*| – Wikipedia.*)\$"],
    "http://.*twitpic.com/" => ["%9twit%Bpic%n ", " on Twitpic\$"],
    "http://(i.)?imgur.com" => ["%Bimgur%n ", ""],
    "http://.+?\.flickr.com" => ["%Bflick%Mr%n ", " -( a set)? on Flickr.*"],
    "http://(www\.)?(media\.)?riemurasia.net" => ["%BRIEMURASIA%n ", "RIEMURASIA"],
    "http://(pics\.)?kuvaton\.com" => ["%BK%Ru%Yv%Ba%Gt%RON%n ", "KuvatON.com - Funny Pics"]
    # TODO
    #"http://img\s+.imageshack.\s{1,3}" => ["%Bimgur%n ", ""]
);

my $max_width = 200;
my @interesting_files = qw/bmp gif jpg jpeg png svg tiff tif swf/;
my @ignore_files = qw/jpeg jpg gif png tiff tif mpg pkg zip sitx sit .ar pdf gz bz2 7z txt js css mp. aiff aif wav snd mod m4a m4p wma wmv ogg swf mov mpeg mpg avi/;

# links from these nicks are displayed in irssi, but not processed by this script
# it can be useful when there is a bot that announces news or a link spammer perhaps
# TODO ei toimi kai
my @ignore_nicks = qw//;

# when printing to the urls window, these words are
# swapped with the words in the message
my %word_colors = (
                        'Maakuth'    => '%mMaakuth%n',
                        '#kuuukkeli' => '%M#kuuukkeli%n',
                        '#nörtti'    => '%R#nörtti%n',
                        'Melchiah'   => '%MMelchiah%n'
                     );

# links from these nicks get special headers
my %nick_headers = (
                       "uutiset" => "%b"
                   );

# if the url is a file other than html, 
# this header is applied to the title
my $url_is_file_header = "File:   ";

# how many titles this script should remember
my $title_cache_size = 100;

# this is an array of individual hashes in perl-talk :)
# it needs to be an array to be able to remove the oldest urls and titles
my @title_cache = (
                   {url => 'title'},
                  );

my $urls_window = Irssi::window_find_name('urls');
# TODO mahdollisuus toimia ilman tätä ikkunaa
if (!$urls_window) {
    Irssi::print("To use the url window, create a window named 'urls' and reload this script.");
    Irssi::print("To create the urls window use the following commands:");
    Irssi::print("(you might be able to use ctrl-mouse drag to select them)");
    Irssi::print("/window new hide");
    Irssi::print("/window name urls");
}

Irssi::signal_add_last('message public', 'public_handler');
Irssi::signal_add_last('message private', 'private_handler');



# TODO numeroiden sijaan vois käyttää sanoja private, public
# run parse with mode 1 (private mode)
sub private_handler {
    parse(1, @_);
}

# run parse with mode 0 (private mode)
sub public_handler {
    parse(0, @_);
}
# http://en.wikipedia.org/wiki/List_of_Internet_top-level_domains
my $top_level_domains = "aero|asia|biz|cat|com|coop|edu|gov|info|int|jobs|mil|mobi|museum|name|net|org|pro|tel|travel";

# main handler
sub parse 
{
    # mode: 1 means private query, 0 means public channel
    # $target isn't used if this subroutine is called as a private one.
    my ($mode, $server, $data, $nick, $mask, $target) = @_;
		$urls_window = Irssi::window_find_name('urls');
    my $url;
    
    # for every link found in message
    # TODO kokeile eri regexpejäkin
    while ($data =~ m{((?:http://|www\.)(?:www\.)?(?:.*?\.)?([^/@\s>]+\.
              $top_level_domains|[a-z][a-z])
              [^\s>]*)}ixg) 
    {
        $url = $1;
        my $endurl; # if link is redirected, this is the final url
				my $title;
        if($url !~ m/^http/) 
        {
            $url = 'http://' . $url;
        }
        ($title, $endurl) = get_title($url);
        #Irssi::print "URL: $url";
        if (defined $endurl) {
            print_title ($mode, $server, $target, $nick, $title, $data, $endurl);
            if (!title_cache_get_title($endurl)) {
                title_cache_add($title, $endurl);
            }
        }
        else {
            print_title ($mode, $server, $target, $nick, $title, $data, $url);
            if (!title_cache_get_title($url)) {
                title_cache_add($title, $url);
            }
        }
    }
    # after printing all the urls,
    # print the full irc message to the urls window
    if ($url and $urls_window) {
        print_message_to_url_window($target, $nick, $data);
    }
}

sub get_title {
    my ($url) = @_;
    my $title;
    my $error; # TODO tuki virheen tunnistamiselle
    my $retries = 2;
    my $resp;
    # large size since some sites have a lot of javascript before the title
    my $max_size = 15000; # bytes
    if ($title = title_cache_get_title($url)) {
        #Irssi::print ("Got title $title for $url from title cache");
        return $title;
    }
    my $ua = LWP::UserAgent->new(
        max_size          => $max_size,
        timeout           => 2,
        protocols_allowed => ['http'],
        agent             => 'Mozilla/5.0'
        #"Accept-Charset"  => "utf-8" # didn't seem to work here
    );
    
    $resp = $ua->get($url, Range => "0-$max_size");

    # if not successful, try to fetch the page again
    if (!$resp->is_success)
    {
        until (!($resp->is_error) or $retries == 0)
        {
            #Irssi::print("Didn't get a response, retrying $retries times");
            $resp = $ua->get($url, Range => $max_size);
            $retries--;
        }
    }
    my $filetype = get_filetype($resp);
    if (!$filetype) {
        $filetype = "Could not determine file type";
        $error = 1;
    }
    my @content = $resp->decoded_content;
    # TODO study this structure to see if extra loop cycles are done redundantly
    if (!$error) {
        foreach my $line ($resp->decoded_content) {
            foreach my $tag (('title', 'h1', 'h2')) {
                if($line =~ m|<[^$tag]*$tag[^>]*>([^<]*)<[^/]*/$tag[^>]*>|si) {
                    $title = $1;
                    $title =~ s/\s+/ /g;
                    $title =~ s/^\s//;
                    $title =~ s/\s$//;
                    decode_entities($title);
              
                    if(length($title) > $max_width) {
                        $title = substr($title, 0, $max_width-1) . "\x{2026}";
                    }
                    last;
                }
            }
        }
    }
    if (!$title) {
        $title = "File:   $filetype";
        $error = 1;
    }

    # check if redirected to another site
    my $endurl = $resp->request->uri;
    if ($endurl ne $url) {
        $endurl =~ s/%/%%/g;
        $title .= ("\n" . $colors{'redirect_color'} . "(redirected to $endurl)%n");
    }
    # if request was unsuccessful
    # return the status line of the http response
    # in case the link was a redirect, include the final url as well
    if (!$resp->is_success)
    {
        if ($title) {
            return "Unsuccessful: " . $resp->status_line . " $title";
        }
        else {
            return "Unsuccessful: " . $resp->status_line;
        }
    }

    # TODO tuki ignorelle
    # ei välttämättä tähän kohti!
    #if (ignore_this_url($url, $nick)) {
    #    $title = "Untitled link";
    #}
    $title ? return ($title, $endurl) : return ("No title found within $max_size bytes", "");
}


sub get_filetype {
    # takes a response object, 
    # returns string if successful, eg. "HTML document text"
    # 0 if not successful
    my ($resp) = @_;
    my $type;

    # this is taken from http://www.cs.ait.ac.th/~on/O/oreilly/perl/prog3/ch16_03.htm
    local (*Reader, *Writer);
    my $pid = open2(\*Reader, \*Writer, "file -");
    # get file type with file via Writer - pipe
    print Writer $resp->content;
    close Writer;
    # get file's output from Reader
    $type = <Reader>;
    chomp $type;
    close Reader;
    waitpid($pid, 0);

    # sample response from `file`:
    # File type: /dev/stdin: HTML document text
    if ($type =~ /\/dev\/stdin: (.*)$/) {
        return $1;
    }
    else {
        Irssi::print ("Filetype not found from 'file' command, returned string was this: $type");
        return 0;
    }
}


# parts of this are borrowed from urlwin.pl by Riku Lindblad
sub print_title {
    # TODO: uus selitysteksti
    # this is used along printing to the window where the title was found
    # in other words, the title is send to two places
    # variable explanations:
    # mode   : public channel (0), private query (1),
    # server : the server where the message is coming from. needed for printing
    # target : channel (public message) or nick (priv msg)
    # nick   : nick of the sender
    # title  : the title found by this script
    # data   : the entire message
    # url    : the url in question
    my ($mode, $server, $target, $nick, $title, $data, $url) = @_;
		#Irssi::print ("mode: $mode, server: $server, target: $target, nick: $nick, title: $title, data: $data, url: $url");
    my $query_window;
    my $header;
		($header, $title) = get_title_header($nick, $title, $url);
		my $title_format = $header . "$title%n";
		# public mode
    if ($mode == 0) {
        $server->print($target, $title_format);
    }
		# private mode
    elsif ($mode == 1) {
        $query_window = Irssi::window_find_item($nick);
        if($query_window)
        {
            $query_window->print($title_format, MSGLEVEL_CRAP);
        }
		}

		# this prints only the title to the urls window
    # the message printing is handled by print_message_to_url_window
    # that, in turn, is done to avoid duplicate messages
    if ($urls_window) {
        # the message level is needed for lastlog searching to work
        $urls_window->print($title_format, MSGLEVEL_CRAP);
    }
}

sub print_message_to_url_window {
    my ($target, $nick, $data) = @_;
    # escape url encoded characters to avoid them being interpreted
    # as irssi's color formats
    $data =~ s/%/%%/g;

    my $data_color = $colors{'data_color'};
    my $text = "$data_color" . "$target " . $data_color  . "$nick " . $data_color . "$data";
    while (my ($key, $value) = (each %word_colors)) {
        if ($text =~ /$key/) {
            $text =~ s/$key/$value/;
        }
    }

    # the message level is needed for lastlog searching to work
    $urls_window->print($text, MSGLEVEL_CRAP);
}


sub get_title_header {
    # TODO better documentation
    # checks if title is already in title cache, returns appropiate color (see $colors )
    # TODO document header format and meanings
		# there are three headers that are added to the beginning of the title:
		# one is for the site, such as youtube
		# the second is for the nick who's sending the link
		# the third marks whether the link is already known in @title_cache
		# also, a header is added for urls that match something in @interesting_files
    my ($nick, $title, $url) = @_;
		my ($site_header, $nick_header, $interesting_header, $title_type_header, $age_header) = "";
		my ($header, $remove_text);
		#Irssi::print ("nick: $nick, title: $title, url: $url");

		# site headers
    # add site header, remove the desired text from the title
    for my $item (keys %site_headers) {
        $header      = $site_headers{$item}[0];
        $remove_text = $site_headers{$item}[1];
				#Irssi::print ("header: $header, remove_text: $remove_text");

				# TODO: document how this works
				# pist se sinne ylös missä noi site_header -jutut on
				#Irssi::print ("checking if $url matches $header");
        if ($url =~ /$item/i) {
            # remove desired text
						#Irssi::print ("$url matches $header");
            if ($title =~ /$remove_text/) {
                $title =~ s/$remove_text//;
								#Irssi::print ("removed text $remove_text");
            }
            $site_header = $header;
        }
    }

    # nick headers
		# TODO tän pitäs tulla vaan jos linkki on normaali uutinen, vai pitäskö
    # TODO tän vois muuntaa sellaseks että se ottais kanaviakin
		# keksi hyvä tapa
    for my $item (keys %nick_headers) {
				#Irssi::print ("Testing nick header for $item $nick_headers{$item}, nick: $nick");
        if ($nick eq $item) {
            #Irssi::print ("Got nick header for $nick, it looks like $nick_headers{$item}this");
            $nick_header = $nick_headers{$item};
        }
    }
		if (!$nick_header) {
				$nick_header = "";
		}

    # is the link interesting?
    foreach my $filetype (@interesting_files) {
        if ($title =~ m/^$url_is_file_header$filetype/i) {
            $interesting_header = $colors {'interesting'};
            #Irssi::print ("the link is interesting");
        }
    }
		if (!$interesting_header) {
				$interesting_header = "";
		}

		# title types: either untitled or titled
    # an untitled link's title typically looks like this
    # File:   UTF-8 Unicode English text
    # TODO could use a variable to set the File:   -message format
    if ($title =~ /^$url_is_file_header/) {
				# untitled links can be either interesting links or just plain untitled ones
        $title_type_header = $colors {'has_no_title'};
        #Irssi::print ("link has no title");
    }
		# links with titles
    else {
				$title_type_header = $colors {'has_title'};
    }

    # age header: is the link already known?
    if (title_cache_get_title($url)) {
            $age_header = $colors {'old_title'};
    }
    else {
            $age_header = $colors {'new_title'};
    }
    # useful debug message
    #Irssi::print ("$site_header lol, $nick_header lol, $title_type_header lol, $age_header lol");
    my $return_header = $site_header . $interesting_header . $title_type_header . $nick_header . $age_header;
    return ($return_header, $title);
}


sub ignore_this_url {
    # check if the url is one of the filetypes and people to be ignored
    # returns 1 if the url should be ignored
    my ($url, $nick) = @_;
    # TODO is this futile?
    foreach my $file_extension (@ignore_files) {
        if ($url =~ m/$file_extension$/i) {
            # url ends with $file_extension
            return 1;
        }
    }
    foreach my $nickname (@ignore_nicks) {
        if ($nick =~ m/^$nickname$/) {
            return 1;
        }
    }
}

sub title_cache_add {
    # add new url to end of title_cache
    # if title_cache_size has been reached, remove the oldest (first) url
    my ($title, $url) = @_;
    my $size = @title_cache;
    if ($size == $title_cache_size) {
        my $dummy = shift @title_cache;
        #Irssi::print("Removed $dummy from the title cache. Current size is ". @title_cache);
    }
    #Irssi::print ("Adding $url to the cache");
    push (@title_cache, {$url => $title});
}

sub title_cache_get_title {
    my ($url) = @_;
    my $size = @title_cache;
    

    # Accessing the structure
    for (my $i = 0; $i <= $#title_cache; $i++) {
        foreach my $key (keys %{$title_cache[$i]}) {
            #Irssi::print ("checking if $url is $key");
            if ($url eq $key) {
                #Irssi::print ("url was the same as key, returning already known url");
                return  $title_cache[$i]{$key};
            }
        } 
    }
}
