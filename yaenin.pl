#!/usr/bin/perl

use warnings;
use strict;

use Data::Dumper;
use Date::Parse;
use Debian::Dpkg::Version;
use Cwd;
use Getopt::Long;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Headers;
use YAML;

my $FILE_CONFIG = "e_packages.yaml";
my $DIR_TMP = getcwd."/tmp";
my $DEBUG = 0;
my $FORCE;

############################################################################

my $help;
GetOptions ( help => \$help
            ,debug => \$DEBUG
            ,force => \$FORCE
);

if ($help) {
    print "$0 [--help] [--debug] [--force]\n"
            ."  --force: rebuilds and re-installs even if it thinks it was done before\n";
}

############################################################################
my $CONFIG = YAML::LoadFile($FILE_CONFIG);
my $UA = new LWP::UserAgent;
my %UNCOMPRESS = %{$CONFIG->{uncompress}};

mkdir $DIR_TMP or die "$! mkdir $DIR_TMP" if ! -e $DIR_TMP;
#

sub download_file{
    my ($url , $file) = @_;
    return if -f $file;
    warn "Downloading $url\n";

    my $req = HTTP::Request->new( GET => $url );
    my $res = $UA->request($req);
    if ($res->is_success) {
            open OUT,">", $file or die "$! $file\n";
            print OUT $res->content;
            close OUT;
    } else {
            die "No success requesting $url ".$res->status_line."\n";
    }
}

sub parse {
    my $package = shift or die "parse \$package";
    my $file = "$DIR_TMP/$package.html";

    my $latest_release=0;

    open my $html,'<',$file or die "$! $file";
    while (<$html>) {
        next if ! /$package/;
        print if $DEBUG;
        my ($release) = /a href="($package-\d.*?)".*?(\d+\-\w+-\d{4} \d\d\:\d\d)/;
        next if !$release;
        print "$release\n" if $DEBUG;
        if ( version_compare($latest_release, $release) ) {
           $latest_release = $release;
        }
    }
    close $html;
    die "I can't find the latest release for package $package\n"
        if !$latest_release;
    if ($DEBUG) {
        print "I found $latest_release for $package\n";
        print " press [ENTER] to continue\n";
        <STDIN>;
    }
    return $latest_release;
}

sub uncompress {
    my $file = shift or die "configure file";
    
    my $cwd = getcwd;

    chdir $DIR_TMP or die "I can't chdir $DIR_TMP";

    my ($ext) = $file =~ m{(tar.\w+)};
    my $cmd = $UNCOMPRESS{$ext} or die "I don't know how to uncompress $ext";
    print "$cmd\n";
    open my $run,'-|',"$cmd $file" or die "$! $cmd $file";
    while (<$run>) {
        print;
    }
    close $run;

    chdir $cwd;
}


sub file_dir {
    my $file = shift or die "file_dir file";
    my ($dir) = $file =~ /(.*)\.(tar.\w+)/;
    die "I can't find dir in $file" if !$dir;
    return $dir;
}

sub configure {
    return if -e "Makefile"     && !$FORCE;
    run("./configure");
}

sub run {
    my $cmd = shift or die "run command";
    open my $run,'-|',$cmd or die $!;
    while (<$run>) {
        print;
    }
    close $run;
    die "ERROR: $? at $cmd in ".getcwd."\n" if $?;
}

sub touch {
    my $file = shift;
    open my $touch,'>', $file or die "$! $file";
    close $touch;
}

sub build {
    return if -e "zz_build"     && !$FORCE;
    run("make");
    touch('zz_build');
}

sub install {
    return if -e "zz_install"   && !$FORCE;
    run("sudo make install");
    run("sudo ldconfig");
    touch('zz_install');
}

sub search_release {
    my ($type,$pkg) = @_;

    download_file("$CONFIG->{url}/$type/$pkg","$DIR_TMP/$pkg.html");

    my $last_release = parse($pkg);
    download_file("$CONFIG->{url}/$type/$pkg/$last_release","$DIR_TMP/$last_release");

    my $dir = $DIR_TMP."/".file_dir($last_release);
    uncompress($last_release) if ! -e $dir;

    my $cwd = getcwd();
    chdir $dir or die "I can't chdir $dir";
    configure();
    build();
    install();
    chdir $cwd or die "I can't chdir $cwd";
    unlink("$DIR_TMP/$pkg.html") or die "$! $DIR_TMP/$pkg.html";
}

sub download {
    my ($type,$pkg) = @_;
    my $filename = search_release($type,$pkg);
}

#################################################################

for my $type (reverse sort keys %{$CONFIG->{packages}}) {
    print "$type\n";
    for my $pkg (@{$CONFIG->{packages}->{$type}}) {
        print "$pkg\n";
        download($type,$pkg);
    }
}
