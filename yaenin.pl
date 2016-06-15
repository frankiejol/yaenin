#!/usr/bin/perl

use warnings;
use strict;

use Data::Dumper;
use Version::Compare;# qw(version_compare);
use Cwd;
use Getopt::Long;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Headers;
use YAML;

my $FILE_CONFIG = "e_packages.yaml";
my $DIR_TMP = getcwd."/tmp";
my $DEBUG = 0;
my ($FORCE , $ALPHA, $BETA, $TEST, $REINSTALL, $PROFILE, $DOWNLOAD_ONLY, $UNINSTALL, $REBUILD);
my $WAYLAND;
my $PREFIX = "/usr/local";
my $WAYLAND;

my $WGET = `which wget`;
chomp $WGET;

my %WAYLAND_FLAGS = (
    efl => ['--enable-egl','--with-opengl=es','--enable-drm','--enable-gl-drm']
    ,enlightenment => ['–enable-wayland-clients','–enable-wayland-egl']
);

my ($me) = $0 =~ m{.*/(.*)};
$me = $0 if !defined $me;
my $FILE_LOG_FLAGS = "$me.log";
my $FLAGS_CHANGED;

flags_changed();
############################################################################

my $help;
GetOptions ( help => \$help
            ,debug => \$DEBUG
            ,force => \$FORCE
            ,beta => \$BETA
            ,alpha => \$ALPHA
            ,test  => \$TEST
              ,rebuild => \$REBUILD
            ,reinstall => \$REINSTALL
            ,profile => \$PROFILE
            ,uninstall => \$UNINSTALL
            ,wayland => \$WAYLAND
            ,"download-only" => \$DOWNLOAD_ONLY
            ,wayland => \$WAYLAND
);

if ($help) {
    print "$0 [--help] [--debug] [--alpha] [--force] [--profile=dev|debug|?]\n"
            ."  --force: rebuilds and re-installs even if it thinks it was done before\n"
            ."  --alpha: allows installing alpha releases\n"
            ."  --test: downloads the packages, but it won't install\n"
            ."  --profile: pass profile to configure of each package\n"
            ."  --download-only: just download, don't build\n"
            ."  --uninstall: uninstall packages\n"
            ;
    exit;
}

if ($PROFILE && $PROFILE =~/debug/i) {
    # TODO test this actually works
    $ENV{CFLAGS}="-O2 -ffast-math -march=native -g -ggdb3";
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

    if ($file =~ m{(/|\.html)$} || !$WGET ) {
        return download_file_lwp(@_);
    } else {
        return download_file_wget(@_);
    }
}

sub download_file_lwp {
    my ($url , $file) = @_;
    my $req = HTTP::Request->new( GET => $url );
    my $res = $UA->request($req);
    if ($res->is_success) {
            open OUT,">", $file or die "$! $file\n";
            print OUT $res->content;
            close OUT;
    } else {
            warn "WARNING: No success requesting $url ".$res->status_line."\n";
    }
}

sub download_file_wget {
    my ($url , $file) = @_;
    print `$WGET -O $file $url`;
}

sub newer {
    my ($f1, $f2) = @_;

    print "$f1 <=> $f2\n" if $DEBUG;
    my $r1 = release_number($f1);
    my $r2 = release_number($f2);
    return Version::Compare::version_compare($r1,$r2);
}

sub release_number {
    my ($file) = @_;
    return 0 if $file =~ m{^\d+$};

    # we remove tar.gz and similars
    $file =~ s/\.\w+\.\w+$//;

    my($release,$status,$status_num) = $file 
        =~ /([\d\.\-]+)(\w?)(?:[a-z]*)(\d*)\.?\w*/;

    die "I can't find release number from $file\n"
        if !$release;

    $release =~ s/(\-|\.)$//;

    $release .=  ".".ord($status or 'z')
                .".".($status_num or 0);

    print "$file: release=$release ".($status or '<NULL>')
            ." ".($status_num or 0)."\n" if $DEBUG;

    return $release;
}

sub parse {
    my $package = shift or die "parse \$package";
    my $file = "$DIR_TMP/$package.html";

    my $latest_release=0;

    open my $html,'<',$file or die "$! $file";
    while (<$html>) {
        next if ! /$package/;
        print if $DEBUG;
        my ($release) = /a href="$package-(\d.*?)".*?(\d+\-\w+-\d{4} \d\d\:\d\d)/;
        next if !$release;
        next if !$BETA && $release =~ /beta/;
        next if !$ALPHA && $release =~ /alpha/;
        my ($ext) = $release =~ m{(tar\..*)};
        next if !$UNCOMPRESS{$ext};
        print "$release\n" if $DEBUG;
        if ( newer($latest_release, $release) ) {
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
    return "$package-$latest_release";
}

sub uncompress {
    my $file = shift or die "File to uncompress required";
    
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
    if ($?) {
        die "File '$file' wrong, remove it and run again.\n";
    }

    chdir $cwd;
}


sub file_dir {
    my $file = shift or die "file_dir file";
    my ($dir) = $file =~ /(.*)\.(tar.\w+)/;
    die "I can't find dir in $file" if !$dir;
    return $dir;
}

sub flags_changed {
    return $FLAGS_CHANGED if defined $FLAGS_CHANGED;

    my $old_flags = load_log_flags();
    my $flags = join ("\n",@ARGV);
    if (!defined $old_flags || $flags ne $old_flags) {
        save_log_flags($flags);
        $FLAGS_CHANGED = 1;
    } else {
        $FLAGS_CHANGED = 0;
    }
    return $FLAGS_CHANGED;
}

sub load_log_flags {
    open my $in ,'<', $FILE_LOG_FLAGS or return;
    return join('',<$in>);
}

sub save_log_flags {
    my $flags = shift;

    open my $out,'>',$FILE_LOG_FLAGS or die "$! $FILE_LOG_FLAGS";
    print $out $flags;
    close $out;
}

sub wayland_flags {
    my $pkg = shift;
    my $wayland_flags = $WAYLAND_FLAGS{$pkg};
    if (!$wayland_flags) {
        warn "WARNING: no wayland flags for $pkg\n";
        $wayland_flags = [];
    }
    push @$wayland_flags,('--enable-wayland');
    return @$wayland_flags;
}

sub configure {
    my $pkg = shift;

    return if -e "Makefile"     && !$FORCE && !$REBUILD && !flags_changed();
    my @cmd =("./configure","--prefix",$PREFIX);
    push @cmd,("--profile=$PROFILE") if $PROFILE;
    push @cmd,("--enable-wayland")   if $WAYLAND;
    run(@cmd);
}

sub run {
    my $cmd = shift or die "run command";
    my $dont_die = shift;

    open my $run,'-|',$cmd or die $!;
    while (<$run>) {
        print;
    }
    close $run;
    die "ERROR: $? at $cmd in ".getcwd."\n" if $? && !$dont_die;
}

sub touch {
    my $file = shift;
    open my $touch,'>', $file or die "$! $file";
    close $touch;
}

sub build {
    return if -e "zz_build"     && !$FORCE && !$REBUILD;
    run("make clean") if $REBUILD;
    run("make");
    touch('zz_build');
}

sub make_uninstall {
    run("make uninstall",1);
    unlink("zz_install");
}

sub make_install {
    return if -e "zz_install"   && !$FORCE && !$REINSTALL;
    run("make install");
    run("ldconfig");
    touch('zz_install');
}

sub build_install {
    my $dir = shift;
    my $pkg = shift;

    my $cwd = getcwd();
    chdir $dir or die "I can't chdir $dir";
    configure($pkg);
    build();
    make_install();
    chdir $cwd or die "I can't chdir $cwd";
}

sub install_package {
    my ($type,$pkg) = @_;

    download_file("$CONFIG->{url}/$type/$pkg/","$DIR_TMP/$pkg.html");

    my $last_release = parse($pkg);
    download_file("$CONFIG->{url}/$type/$pkg/$last_release","$DIR_TMP/$last_release");

    return if $DOWNLOAD_ONLY;
    my $dir = $DIR_TMP."/".file_dir($last_release);
    uncompress($last_release) if ! -e $dir;

    build_install($dir,$pkg) if !$TEST;

    unlink("$DIR_TMP/$pkg.html") or die "$! $DIR_TMP/$pkg.html";
}

sub uninstall {
    opendir my $ls,$DIR_TMP or die "$! $DIR_TMP";
    while (my $file = readdir $ls) {
        next if ! -d "$DIR_TMP/$file";
        chdir "$DIR_TMP/$file";
        make_uninstall();
        chdir "..";
    }
    closedir $ls;
}

#################################################################

mkdir $DIR_TMP or die "$! $DIR_TMP" if ! -e $DIR_TMP;
umask('0022');
if ($UNINSTALL) {
    uninstall();
    exit;
}
for my $type (reverse sort keys %{$CONFIG->{packages}}) {
    print "$type\n";
    for my $pkg (@{$CONFIG->{packages}->{$type}}) {
        print "$pkg\n";
        install_package($type,$pkg);
    }
}
