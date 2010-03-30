#! /usr/bin/perl -w

use strict;

# Read in from config

my $database = $ENV{HOME} . '/current/programs/instiki_svn/db/production.db.sqlite3';
my $destination = $ENV{HOME} . '/public_html/nforge';
my $lastID = 0;

#Haven't got the modules.  Darn.  Let's map out the scheme.

#Select pages from last time we ran.

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

my $initrows = getRows($database,\@initcols,\@inittables);

foreach my $row (@$initrows)
{
    if ($$row{'password'} ne '')
    {
	add_to_htpasswd($$row{'name'}, $$row{'password'});
	add_to_htaccess($$row{'id'}, 'Requre User ' . $$row{'name'});
    }
    print "Would now make " . $destination . '/' . $$row{'id'} . "\n";
    print "And link it to " . $destination . '/' . $$row{'address'} . "\n";
#    mkdir($destination . '/' . $$row['id']);
#    link($destination . '/' . $$row['address']);
}

my @datacols = qw/
revisions.id
revisions.content
revisions.updated_at
revisions.author
revisions.ip
pages.id
pages.name
pages.web_id
/;

my @datatables = qw/
pages
revisions
/;

my @dataconditions = qq/
pages.id=revisions.page_id
revisions.id>$lastID
/;

my $datarows = getRows($database,\@datacols,\@datatables,\@dataconditions);

foreach my $r (@$datarows)
{
    my $fileid = $destination . "/" . chomp($$r{'pages.web_id'}) . "/" . $$r{'pages.id'};
    # encode spaces as well?
    my $safename = $$r{'pages.name'};
    $safename =~ s(/)(%23); # check code for /
    my $filename = $destination . "/" . chomp($$r{'pages.web_id'}) . "/" . $safename;
    my $action = (-r $filename ? ' edited ' : ' created ');
    print "Would now write to " . $fileid . "\n";
    print "And link it to     " . $safename . "\n";
    print "Then commit with   " . $$r{'revisions.author'} . $action . $$r{'pages.name'} . ' on ' . $$r{'revisions.updated_at'} . ' from ' . $$r{'revisions.ip'} . "\n";
#    open(FILE,">" . $fileid)
#	or die;
#    print FILE $r{'revisions.content'};
#    close(FILE);
#    link($fileid,$filename);
#    bzr_commit($r{'revisions.author'} . $action . $r{'pages.name'} . ' on ' . $r{'revisions.updated_at'} . ' from ' . $r{'revisions.ip'});
    $lastID = $$r{'revisions.id'} if ($$r{'revisions.id'} > $lastID);
}

print "Last identifier was " . $lastID . "\n";

sub getRows
{
    my ($db,$cols,$tabs,$conds) = @_;

    my $sql = "'SELECT " . join(',',@$cols) . ' FROM ' . join(' JOIN ', @$tabs) . ($#$conds > 0 ? ' WHERE ' . join(' AND ', @$conds): '') . ";'";
    my @rows;
    my @r;
    my $sep = "SEP".$$;

    my @data = qx(sqlite3 -separator $sep $db $sql);

    my %row = ();
    my $col;

    while ($_ = shift @data)
    {
	if (/^\d+$sep/)	{
	    if (%row) {
		chomp($row{$col});
		push (@rows,\%row);
		%row = ();
		push(@$cols,shift(@$cols));
	    }
	}
	my @line = split($sep, $_);
	$col = $$cols[0];
	$row{$col} .= shift(@line);

	while (@line) {
	    push(@$cols,shift(@$cols));
	    $col = $$cols[0];
	    $row{$col} .= shift(@line);
	}
    }

    return \@rows;
}
