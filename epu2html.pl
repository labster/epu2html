#  epu2html v0.1
# by Brent Laabs, April 2012
# Licensed under Creative Commons-Attribution License (CC BY 3.0).
# http://creativecommons.org/licenses/by/3.0/

use warnings;
use strict;
use feature qw/say switch/;
use CGI qw/:standard/;   #for the html tags
use Cwd 'abs_path';
use File::Basename;
use HTML::Entities qw/encode_entities/;

my $can_hyphenate = 1;

eval "use TeX::Hyphen";
my $hyp;
if ($@) {
    $can_hyphenate = 0;
} else {
    $hyp = new TeX::Hyphen;
}

##### You might need to configure this one #######
## if the CSS is not in the same folder as this script
   # my $path_to_css = '/path/to/kei.css';
   my $path_to_css = dirname(abs_path($0)) . '/kei.css';
## if you want to name it something other than kei.css
   my $stylesheet = "kei.css";

my $path_to_css_shell = $path_to_css;
$path_to_css_shell =~ s/'/'\''/g;
`cp '$path_to_css_shell' .`;
-e "./kei.css" or warn "Could not copy CSS file from $path_to_css.";

my $columns = 70;  #change with -c## option
my $multi_file = (grep { $_ !~ /^-/ } @ARGV) - 1;
my $use_stdout = 0; #change with -o option
my $quiet_mode = 0; #change with -q
my $strict_mode =0; #change with -s
my $hyphenation =0; # change with -h
my $num_files_processed = 0;
my %contains_unknown_paragraphs;

# my $style = slurp('/web/img/foo.css');


# FILE PROCESSING
while (my $filename = shift @ARGV ) {
    # command line switches
    $filename =~ /^-c(\d+)$/ and $columns = $1 and next;
    $filename =~ /^-utf8$/ and charset('utf-8') and next;
    $filename =~ /^-o$/ and $use_stdout = 1 and next;
    $filename =~ /^-q$/ and $quiet_mode = 1 and next;
    $filename =~ /^-s$/ and $strict_mode = 1 and next;
    $filename =~ /^-h$/ and $hyphenation = 1 and next;

    die "Install TeX::Hyphen to hyphenate" if ($hyphenation && !$can_hyphenate);

    -e $filename or die "Cannot locate $filename";
    -r _ or die "Cannot read $filename";
    -f _ or die "$filename is not a plain file";


    transcode_file($filename);
    $num_files_processed++;  $num_files_processed >= 256 and die "too many";

}


#end report
unless ($quiet_mode) {
  say '-' x 20;
  say "$num_files_processed files processed";
  if (keys %contains_unknown_paragraphs) {
    say "These files have unknown paragraphs:";
    say $_ for sort keys %contains_unknown_paragraphs;
  }
}



sub transcode_file {
    my $filename = shift;
    my @lines = slurp($filename);
    # say "Lines:", scalar(@lines);

    our $author_guess = '';
    our $title_guess  = '';

    my $shorttitle = $filename =~ m|/| ? pop([split m|/|, $filename]) : $filename;
    my $outfilename = $shorttitle;
    $outfilename =~ s/\.txt$/.html/;
    $outfilename = sprintf("%02d", $num_files_processed) . $outfilename if $multi_file;
         #say $outfilename; say $multi_file; exit;

    my $fh;
    if ($use_stdout) { $fh = *STDOUT; }
    else { open $fh, ">", $outfilename; }

    say $fh start_html(-title=>$shorttitle,
                  -style=>{'src'=>$stylesheet},
                 # -head=>style({-type=>'text/css'}, $style),
                  );


    push @lines, ''; # squash over-index error
    # need a proper iterator so we can look at nearby lines
    for (my $i = 0; $i < $#lines; $i++) {
        my $line = $lines[$i];

        # $line = general_formatting($line);
        $line =~ /^(\s*)/ and
        my $indent = length $1;
        $line =~ /\S/ or $indent = 0;
        #print $indent, " ";  next;

        ## Empty line ##
        if ($line eq '') { say $fh "<p />"; next;}

        ## Music ##
        if ($line =~ m| \s* /[\*♪] |x or $line =~ m|^\s*\<\<|) {
           if ($line =~ m|[\*♪]/ \s*|x or $line =~ m|^\s*\<\<|) {
               #single-line song, good
               say $fh p({-class=>"music"}, general_formatting($line));
               next;
           }
           elsif (grep { m|[\*♪]/\s*| } @lines[$i+1 .. $i+4]) {  #4-line lookahead
               for (1..4) {
                   $i++;
                   $line .= "<br />\n" . $lines[$i];
                   $lines[$i] =~ m|[\*♪]/\s*| and last;
               }
               say $fh p({-class=>"music"}, general_formatting($line));
               next;
           }
           # else ... it isn't music, so continuing
        }

        ## Centered text ##
        if ( is_centered($line, \@lines, $i) ) {
            while ( $lines[$i+1] =~ /\w/ and is_centered($lines[$i+1], \@lines, $i, 1) ) {
              $i++;
              $line .= "<br />\n" . $lines[$i];
            }
            #my $class = ($line =~ /[[:lower:]]{2,}/) ? 'title' : 'bigtitle';
            my $class = 'title';
            $class = 'cast' if $i > .9*$#lines;
            #$line =~ s/\s{2,}/ /g;
            say $fh p({-class=>$class}, general_formatting($line));
            $title_guess and $author_guess or get_author_title($line);
            next;
        }

        ## Normal paragraphs ##
        if ( $indent >= 4 and $indent <= 9 ) {
            while ($lines[$i+1] ne '' and $lines[$i+1] !~ /^\s{2,}/) #allow 1 space for errors
               { $line .= "\n" . $lines[$i+1]; $i++ }
            if ($line =~ /^\s*\>[^\w]/)
               { say $fh p({-class=>'code'}, general_formatting($line)); next; }
            if ($line =~ /^\s*"/ and $line !~ /\n/s and $line !~ /".*"/) {
               #this is a quote trying really hard to look like a paragraph
               my $x = join "\n", @lines[$i..$i+10];
               if ($x =~ /^\s*--/m) { #make sure it's quotelike
                  while (1) { $line .= "\n<br />" . $lines[$i+1]; $i++; $lines[$i] =~ /^\s*--/ and last; }
                  say $fh p({-class=>'quote'}, $line);
                  next;
               }
            }
            say $fh p(general_formatting($line));
            next;
        }



        ## Lyrics or Email or Console ##
        if ( $indent == 0 ) {
          if ( $line =~ /\@|[[:punct:]]{4,}/ #lots of punctuation
            or ($line =~ /^\w+:/ and $line !~ /^http:/)  #looks like email/http header
                                             # but is not actually a hyperlink
            or $line =~ /^\/|\>/             #path or prompt start
            or $line =~ /[A-Z]/ && $line !~ /[a-z]/   #all caps
            or $lines[$i+1] =~ /^\s/) {    #next line indented
                        ## $ >GUESS CONSOLE MODE  (email/durandal/code)
              #slurp past \n\n
              while ($i+1 <= $#lines and $lines[$i+1] !~ /^\s{4,9}/
                      and !is_centered($lines[$i+1], \@lines, $i)) {
                  #$lines[$i+1] eq '' and $lines[$i+1] = "<br />";
                  $line .= "\n" . $lines[$i+1];
                  $i++;
              }
              $line =~ s/\</&lt;/g;
              say $fh p({class=>'console'}, $line, "\n<br />");
          }
          elsif ( $line =~ /\s{4,}/ ) { #guess dual-column lyrics/cast
              my ($lhs, $rhs) = split /\s{4,}/, $line;
              my $table = Tr(td($lhs), td($rhs));
              while ($lines[$i+1] ne '') {
                 my $curr = $lines[$i+1];
                 my $over = 0;
                  $i++;
                  if ($curr =~ /^\s{15,}/) {  # empty left column
                      $curr =~ s/^\s{15,}//;
                      $table .= Tr(td(), td($curr)). "\n";
                      #$rhs .= "<br />\n" . $curr;
                      #$lhs .= "<br />\n";
                      next;
                  }
                  if ($curr =~ /^\s{1,14}/) {  #indented left col (hi t'skaia!)
                      $curr =~ s/^(\s)*// and $over = length $1;
                      # $lhs .= "\n" . $curr;
                      # next;
                  }
                  if ($curr =~ /\s{2,}/) {
                      my ($l, $r) = split /\s{2,}/, $curr;
                      #$lhs .= ($over ? "\n" . (' ' x $over) : "<br />\n" ). $l;
                      #$rhs .= "<br />\n$r";
                      $table .= Tr(
                          td($over ? span({-class=>'ind'}, (' ' x $over), $l) : $l),
                          td($r)). "\n";
                      next;
                  }
                  #default...
                  # $lhs .= "<br />\n" . $curr;
                  # $rhs .= "<br />\n";
                  $table .= Tr(td($curr), td()) . "\n";
              }
              #say $fh table({-class=>'split'}, TR(
              #   td({-class=>'lcast'},  general_formatting($lhs)),
              #   td({-class=>'rlyric'}, general_formatting($rhs))
              #));
              #say $fh div({-class=>'split'},
              #   p({-class=>'lcast'},  general_formatting($lhs)),
              #   p({-class=>'rlyric'}, general_formatting($rhs))
              #);
              say $fh table({-class=>'split'}, $table);

          }
          else { #guess lyrics
              #slurp until end of stanza
              while ($lines[$i+1] =~ /\S/) { $line .= "<br />\n" . $lines[$i+1]; $i++ }
              say $fh p({-class=>'lyrics'}, general_formatting($line));
          }
        next;
        }

       ## default ##
       say $fh p({-class=>'unknown'}, general_formatting($line));
       $contains_unknown_paragraphs{$outfilename} = 1;


    }  #end for

    print $fh end_html;

    close $fh unless $use_stdout;
    unless ($quiet_mode) {
      say "Processed: $filename";
      say "Title: $title_guess";
      say "Author: $author_guess";
    }

    my $metafilename = $outfilename;
    $metafilename =~ s/\.html$/\.meta/;
    my $meta;
    open $meta, ">", $metafilename;
    say $meta $title_guess;
    say $meta $author_guess;
    close $meta;

}

sub is_centered {
    my ($line, $lines, $i, $continuing) = @_;
    return 0 unless $line;
    # $continuing is the T'skaia fix

    $line =~ /^(\s{2,})/;
    my $frontspace = length($1) || 0;

    return(
        $frontspace > 0
          # more than indent OR this is a long line in the middle of a centered block
        and ($frontspace > 9 or $continuing && is_centered($lines->[$i+2]) )
          # this actually looks centered                 ...ish
        and abs($frontspace - ($columns - length $line)) <= 5 );
}


sub general_formatting {
    my $line = ' ' . shift . ' ';
    $line =~ s/<br \/>/~ranma~/g;
    $line = encode_entities($line, q/<>&"'/);
    $line =~ s/~ranma~/<br \/>/g; #ranma... will never appear in UF!

    #underlining and italics
    # $line =~ s/(\W)-(\w.*?\w\W?)-(\W)/$1<i>$2<\/i>$3/g;
    $line =~ s/(\W)-(\w(?:.*?\w)??\W?)-(\W)/$1<i>$2<\/i>$3/g;

    $line =~ s/(\W)_(\w(?:.*?\w)?\W?)_(\W)/$1<u>$2<\/u>$3/g;

    $line =~ s/ -(?: |\Z)/&mdash;/g;

    #canonical hyperlink
    $line =~ s|(http://[^ \n<]+)|<a href="$1">$1</a>|g;

    $line = hyphenate($line) if ($hyphenation);

    return $line;
}

sub hyphenate {
    my $line = shift;
    # Note: not using \w because TeX::Hyphen's set of chars that may be in a
    # hyphenatable word is not the same as \w, but we still want to hyphenate
    # words enclosed in such chars.
    while ($line =~ m/(?:[^a-zA-Z]|^)([a-zA-Z]+)(?:[^a-zA-Z]|$)/g) {
        my $word = $1;
        my $new = $word;
        for my $pos (reverse $hyp->hyphenate($new)) {
            substr($new, $pos, 0) = '&shy;';
        }
        my $p = pos($line);
        substr($line, $-[1], $+[1] - $-[1]) = $new if $new ne $word;
        pos($line) = $p + (length($new) - length($word));
    }

    return $line;
}


sub slurp {
#just a little function to grab a file into memory
    my $filename = shift;
    my ($f, $contents);
    open($f, "<", $filename) or die "bad filename given: $filename";

    local $/ = undef;
    $contents = <$f>;
    $contents =~ s/\t/        /g;    #tabs to 8 spaces
    return $contents unless wantarray;
    return split /\n/, $contents;
}

sub is_front_matter {
    my $front_rx = qr/from another time|Eyrie Productions|UNDOCUMENTED/;
    return( shift =~ $front_rx );
}

sub is_author {
    # in no particular order (common last names in title avoided like "Rose")
    my $author_rx = qr/^\s*by|Hutchins|Anne|MegaZone|Overstreet|Depew|Mui|Meadows|Martin|Barlow|ReRob|Mann|Moyer|Collier/;
    return( shift =~ $author_rx );
}

sub get_author_title {
  my $line = shift;
  our $author_guess;
  our $title_guess;

  $line =~ s/\n//g;
  $line =~ s|<br />| |g;
  $line =~ s|^\s*||g;
  $line =~ s|\s{3,}|, |g;

  is_front_matter($line) and return;
  is_author($line) and $author_guess = $line and return;
  $title_guess and return;
  $line =~ /\d[\d:]\d\d/ and return;
  $title_guess = $line;

  return;
}
