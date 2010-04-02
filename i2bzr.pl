#! /usr/bin/perl -w

use strict;
use DBI();
use Apache::Htpasswd;
use Apache::Htaccess;
use URI::Escape;

my $database = "instiki";
my $host = "localhost";
my $user = "instiki";
my $pass = "SVt6GX1rmqWw";

my $destination = '/var/www/nForge';
my $htpasswd_file = $destination . '/.htpasswd';

if (!-e $htpasswd_file) {
    open (HTPASSWD, ">$htpasswd_file");
    close HTPASSWD;
}

my $config = $ENV{HOME} . '/.i2bzr.cfg';
my $lastID = 28250;
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
    if (!-e $destination . '/'. $row->{'id'}) {
	mkdir($destination . '/' . $row->{'id'});
    }
    if (!-e $destination . '/'. $row->{'address'}) {
	symlink($destination . '/' . $row->{'id'},$destination . '/' . $row->{'address'});
    }

    if ($row->{'password'} && ($row->{'password'} ne '')) {
	my $htaccess = new Apache::Htaccess($destination . '/' . $row->{'id'} . '/' . '.htaccess');
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

my @datatables = qw/
pages
revisions
/;

my @dataconditions = ("pages.id=revisions.page_id","revisions.id>$lastID");

my $datasql = "SELECT " . join(',',@datacols) . ' FROM ' . join(' JOIN ', @datatables) . ' WHERE ' . join(' AND ', @dataconditions) . ";";


my $data = $dbh->prepare($datasql);
$data->execute();

while (my $r = $data->fetchrow_hashref()) {
    my $fileid = $destination . "/" . $r->{'web_id'} . "/" . $r->{'page_id'};
    my $safename = uri_escape($r->{'name'});
    my $filename = $destination . "/" . $r->{'web_id'} . "/" . $safename;
    my $action = (-r $filename ? ' edited ' : ' created ');
    print "Would now write to " . $fileid . "\n";
    print "And link it to     " . $safename . "\n";
    print "Then commit with   " . $r->{'author'} . $action . $r->{'name'} . ' on ' . $r->{'updated_at'} . ' from ' . $r->{'ip'} . "\n";
#    open(FILE,">" . $fileid)
#	or die;
#    print FILE $r{'revisions.content'};
#    close(FILE);
#    link($fileid,$filename);
#    bzr_commit($r{'revisions.author'} . $action . $r{'pages.name'} . ' on ' . $r{'revisions.updated_at'} . ' from ' . $r{'revisions.ip'});
    $lastID = $r->{'id'} if ($r->{'id'} > $lastID);
}

if (open (CONFIG, ">$config")) {
    print CONFIG "LastRevision = " . $lastID . "\n";
}
