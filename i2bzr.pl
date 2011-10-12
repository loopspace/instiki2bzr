#! /usr/bin/perl -w

use strict;
use DBI();
use Apache::Htpasswd;
use Apache::Htaccess;
use URI::Escape;

# Since we're writing into the www root, make sure we can be read
umask(022);

my $database = "instiki";
my $host = "localhost";
my $user = "instiki";
my $pass = "SVt6GX1rmqWw";
my $bzrprog = "/usr/bin/bzr";
my $destination = '/var/www/nForge';
my $htpasswd_file = $destination . '/.htpasswd';

# Make sure the htpasswd file exists
if (!-e $htpasswd_file) {
    open (HTPASSWD, ">$htpasswd_file");
    close HTPASSWD;
}

# Figure out where we're up to in the revision list
my $config = $ENV{HOME} . '/.i2bzr.cfg';
my $lastID = 0;
if (-e $config) {
if (open (CONFIG, $config)) {
    while (<CONFIG>) {
	if (/^\s*LastRevision\s*[=:]?\s*(\d+)/) {
	    $lastID = $1;
	}
    }
    close CONFIG;
}
}

my $htpasswd = new Apache::Htpasswd($htpasswd_file);
my @htusers = $htpasswd->fetchUsers();
my $dbh = DBI->connect("DBI:mysql:database=" . $database . ";host=" . $host, $user, $pass, {'RaiseError' => 1});

#Need to know:
# 1. content -> file contents
# 2. page_id -> file name
# 3. web_id  -> directory
# 4. page_name -> file name?  Should be unique, but id is guaranteed, perhaps a symlink?
# 5. web_address -> directory? Ditto
# 6. author -> committer
# 7. ip -> committer's email(?)
# 8. web_name -> access name
# 9. web_passwd -> access password

# Initialise:

my @initcols = qw/
id
name
password
address
/;

my @inittables = qw/
webs
/;

my $initsql = "SELECT " . join(',',@initcols) . ' FROM ' . join(' JOIN ', @inittables) . ";";

my $init = $dbh->prepare($initsql);
$init->execute();

while (my $row = $init->fetchrow_hashref()) {
    my $dir = $destination . '/' . $row->{'id'};
    if (!-e $dir) {
	mkdir($dir);
	bzr_init($dir);
    }
    if (!-e $destination . '/'. $row->{'address'}) {
	symlink($dir,$destination . '/' . $row->{'address'});
    }

    if ($row->{'password'} && ($row->{'password'} ne '')) {
	my $htaccess = new Apache::Htaccess($dir . '/' . '.htaccess');
	$htaccess->directives('AuthType' => 'Basic', 'AuthName' => '"Access to ' . $row->{'name'} . '"', 'AuthUserFile' => $htpasswd_file, 'Require user' => $row->{'name'});
	$htaccess->save();
	if (grep($_ eq $row->{'name'}, @htusers)) {
	    $htpasswd->htpasswd($row->{'name'}, $row->{'password'}, {'overwrite' => 1});
	} else {
	    $htpasswd->htpasswd($row->{'name'}, $row->{'password'});
	}
    }
}


my @datacols = qw/
revisions.id
revisions.content
revisions.updated_at
revisions.author
revisions.ip
revisions.page_id
pages.name
pages.web_id
/;

my @metacols = qw/
id
name
author
updated_at
ip
/;

my @datatables = qw/
revisions
pages
/;

my @dataconditions = ("pages.id=revisions.page_id","revisions.id>$lastID");

my @dataorder = qw/
revisions.id
/;

# Maybe should put a 'LIMIT' statement here - the initial list is quite large!
# Looking at the memory usage, it probably reads in a lot into memory

my $datasql = "SELECT " . join(',',@datacols) . ' FROM ' . join(' JOIN ', @datatables) . ' WHERE ' . join(' AND ', @dataconditions) . ' ORDER BY ' . join(',',@dataorder) . ";";


my $data = $dbh->prepare($datasql);
$data->execute();

while (my $r = $data->fetchrow_hashref()) {
    my $dir =  $destination . "/" . $r->{'web_id'};
    my $fileid = $dir  . "/" . $r->{'page_id'};
    my $new = (-r $fileid ? 0 : 1);
    open(FILE,">" . $fileid)
	or die;
    print FILE $r->{'content'};
    close(FILE);
    open(META, ">>" . $fileid . ".meta")
	or die;
    print META "---\n";
    for (my $j = 0; $j <= $#metacols; $j++) {
	print META $metacols[$j] . ": " . $r->{$metacols[$j]} . "\n";
    }
    my $action = ' edited ';
    if ($new) {
	$action = ' created ';
	bzr_add($dir,$fileid);
	bzr_add($dir,$fileid . ".meta");
    }
    bzr_commit($dir,$r->{'author'} . $action . $r->{'name'} . ' on ' . $r->{'updated_at'} . ' from ' . $r->{'ip'});
    $lastID = $r->{'id'} if ($r->{'id'} > $lastID);
}

if (open (CONFIG, ">$config")) {
    print CONFIG "LastRevision = " . $lastID . "\n";
}

$dbh->disconnect;
exit;

sub bzr_init {
    my ($dir) = @_;
    chdir($dir);
    system($bzrprog,"init");
}

sub bzr_add {
    my ($dir,$file) = @_;
    system($bzrprog,"add",$file);
}

sub bzr_commit {
    my ($dir,$msg) = @_;
    chdir($dir);
    system($bzrprog,"commit","-m",$msg);
}
