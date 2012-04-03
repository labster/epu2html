#!/usr/local/bin/perl
use warnings;
use feature 'say';
use Cwd 'abs_path';
use File::Basename;

### You might need to configure this one ###
# if the CSS is not in the same folder as this script
    # $path_to_css = '/path/to/kei.css';
$path_to_css = dirname(abs_path($0)) . '/kei.css';

# Read directory

my $dir = shift // die "Needs one argument: directory to build into";
-d $dir or die "$dir does not exist or is not a directory";

# Make META-INF

-e "$dir/META-INF" or `mkdir '$dir/META-INF'`;
-e "$dir/META-INF" or die "couldn't create directory META-INF";

open $container, ">$dir/META-INF/container.xml" or die "can't write";
print $container <<CONTN;
<?xml version='1.0' encoding='utf-8'?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
  <rootfiles>
    <rootfile media-type="application/oebps-package+xml" full-path="yuri.opf"/>
  </rootfiles>
</container>
CONTN
close $container;

# Make OPF

opendir $dirh, $dir;
my @rawfiles = readdir $dirh;
closedir $dirh;

for (@rawfiles) {
  /(?:\.html)/ and push @files, $_;
}
$path_to_css =~ s/'/'\''/g;
`cp '$path_to_css' '$dir'`;
-e "$dir/kei.css" or die "no copy";

@files = sort @files;  #lexically sort for now

load_metafiles();  #makes %titles and %authors keyed on filename
$best_match_author = '';
$best_match_author = (length $_ > length $best_match_author ? $_ : $best_match_author) for values %authors;

open $opf, ">$dir/yuri.opf" or die "can't write OPF";
print $opf <<FPF;
<?xml version='1.0' encoding='UTF-8'?>

<package xmlns:opf="http://www.idpf.org/2007/opf" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
  <metadata>
    <dc:identifier id="id" opf:scheme="URI">http://www.eyrie-productions.com/UF/</dc:identifier>
    <dc:creator opf:file-as="Hutchins, Benjamin D.">$best_match_author</dc:creator>
    <dc:title>$first_title</dc:title>
    <dc:language xsi:type="dcterms:RFC4646">en</dc:language>
    <dc:subject>Fanfiction -- Fiction</dc:subject>
    <dc:date opf:event="conversion">2012-02-15</dc:date>
    <dc:source>http://www.eyrie-productions.com/UF/</dc:source>
    <dc:identifier id="BookId" opf:scheme="ISBN">123456789X</dc:identifier>
  </metadata>
  <manifest>
    <item href="kei.css" id="css1" media-type="text/css"/>
FPF

   #build manifest
   my $i = 0;  $spine = '';  # $guide = '';
   for $f (@files) {
     $i++;
     print $opf qq{    <item href="$f" id="item$i" media-type="application/xhtml+xml"/>\n};
     $spine .= qq{<itemref idref="item$i" linear="yes"/>\n};
     # $guide .= 
   }

print $opf <<FOO;
    <item href="toc.ncx" id="ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx">
FOO

print $opf $spine;

print $opf "  </spine>\n";

#print $opf <<OMGHAI;
#  <guide>
#    <reference href="0.html" type="toc" title="Contents"/>
#    <reference href="$files[0]" type="cover" title="Cover"/>
#  </guide>
#OMGHAI

print $opf "</package>\n";


close $opf;

# Make NCX

open $ncx, ">$dir/toc.ncx";

print $ncx <<KNKX;
<?xml version='1.0' encoding='UTF-8'?>
<!DOCTYPE ncx PUBLIC '-//NISO//DTD ncx 2005-1//EN' 'http://www.daisy.org/z3986/2005/ncx-2005-1.dtd'>

<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="en">
  <head>
    <meta name="dtb:uid" content="123456789X"/> <!-- same as in .opf -->
    <meta name="dtb:depth" content="1"/> <!-- 1 or higher -->
    <meta name="dtb:totalPageCount" content="0"/> <!-- must be 0 -->
    <meta name="dtb:maxPageNumber" content="0"/> <!-- must be 0 -->
  </head>
  <docTitle>
    <text>Undocumented Features - $first_title</text>
  </docTitle>
  <navMap>
KNKX

$i = 0;
for $f (@files) {
$i++;
#my $metafile = $f;
#my $label = '';
#$metafile =~ s/\.html$/.meta/;
#if (-e $metafile) {
#  my $meta;
#  open $meta, $metafile;
#  $label = <$meta>;
#}
#else {$label = $f; }
#chomp $label;

print $ncx <<MINBAR;

    <navPoint id="item$i" playOrder="$i">
      <navLabel>
        <text>$labels{$f}</text>
      </navLabel>
      <content src="$f"/>
    </navPoint>
MINBAR
}

print $ncx <<FOOBAR;
  </navMap>
</ncx>
FOOBAR


sub load_metafiles {
for $f (@files) {
my $metafile = $f;
my $label = '';
$metafile =~ s/\.html$/.meta/;
if (-e $metafile) {
  my $meta;
  open $meta, $metafile;
  $label = <$meta>;
  $author = <$meta>;
}
else {$label = $f; $author = ''; }
chomp $label;
chomp $author;

$labels{$f} = html_escape($label);
$authors{$f} = html_escape($author);
$first_title //= html_escape($label);
}
}


sub html_escape {
# Gets rid of all the HTML control characters
# the non-URL version of escape_string above
  BEGIN {
     use vars '%html_escape';
     %html_escape = ( '&'=>'&amp;',  '<'=>'&lt;', '>'=>'&gt;',
                      "'"=>'&apos;', '"'=>'&quot;' );
  }

  my $s = shift;
  $s =~ s/(['>&<"])/$html_escape{$1}/g;
  return $s;
}