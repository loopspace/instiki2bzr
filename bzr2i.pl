#! /usr/bin/perl -w

use strict;
use DBI();
use Getopt::Long;

my $dbprod = "production.db.sqlite3";
my $database = "DBI:SQLite:dbname=";
my $user = "";
my $pass = "";
my $bzrprog = "/usr/bin/bzr";
my $dir = ".";
my $debug;

my $wikiname;
my $lname;
my $css;
my $wpass;
my $web_id = 1;

my @cols;
my $table;
my $sql;
my $sth;

GetOptions (
    "w|wiki=s" => \$wikiname,
    "d|dir=s" => \$dir,
    "a|address=s" => \$lname,
    "p|password=s" => \$wpass,
    "c|css=s" => \$css,
    "db|database=s" => \$dbprod,
    "debug" => \$debug
    );

die("$dbprod already exists.\n") if (-e $dbprod);
die("No wiki specified.\n") unless $wikiname;

my $dbh = DBI->connect($database . $dbprod, $user, $pass , {'RaiseError' => 1});

if (!$lname) {
    ($lname = lc($wikiname)) =~ s/\s+//g;
}

# Create database

create_db($dbh, $wikiname, $lname, $wpass, $css);

# Slurp in the filenames

my @pages = glob($dir . "/*.meta");
my $npages = @pages;

# Now create the pages
# INSERT INTO "pages" (id, created_at, updated_at, web_id, name) VALUES (?,?,?,?,?)

@cols = qw/
id
created_at
updated_at
web_id
name
/;

$table = "pages";

$sql = "INSERT INTO " . $table . ' (' . join(', ', @cols) . ') VALUES (' . join(', ', map {"?"} @cols ) . ');';

$sth = $dbh->prepare($sql);

for (my $i = 0; $i < $npages; $i++) {
    my ($id, $created_at, $updated_at, $name);
    open(META, $pages[$i])
	or die "Couldn't open $pages[$i] for reading\n";
    ($id = $pages[$i]) =~ s/\.meta//;
    $id =~ s%.*/%%;
    my $nl = 0;
    my $data;
    while (<META>) {
	if ($nl % 6 == 0) {
	    $data = "";
	} else {
	    $data .= $_;
	}
	if ($nl == 5) {
	    ($created_at = $_) =~ s/updated_at: //;
	    chomp($created_at);
	}
	$nl++;
    }
    my @data = split("\n", $data);
    ($name = $data[1]) =~ s/name: //;
    ($updated_at = $data[3]) =~ s/updated_at: //;
    debug("Creating page $id, $name, $updated_at");
    $sth->execute($id,$created_at,$updated_at,$web_id,$name);
}


# Now populate the content
# INSERT INTO "revisions" (created_at, updated_at, revised_at, page_id, content, author, ip)

@cols = qw/
created_at
updated_at
revised_at
page_id
content
author
ip
/;

$table = "revisions";

$sql = "INSERT INTO " . $table . ' (' . join(', ', @cols) . ') VALUES (' . join(', ', map {"?"} @cols ) . ');';

$sth = $dbh->prepare($sql);

# Along the way, pick up the wiki references

my @references;

for (my $i = 0; $i < $npages; $i++) {
    my ($updated_at, $page_id, $content, $author, $ip);
    my $file;
    open(META, $pages[$i])
	or die "Couldn't open $pages[$i] for reading\n";
    ($file = $pages[$i]) =~ s/\.meta//;
    ($page_id = $file) =~ s%.*/%%;
    my $nl = 0;
    my $data;
    while (<META>) {
	if ($nl % 6 == 0) {
	    $data = "";
	} else {
	    $data .= $_;
	}
	$nl++;
    }
    my @data = split("\n", $data);
    ($author = $data[2]) =~ s/author: //;
    ($updated_at = $data[3]) =~ s/updated_at: //;
    ($ip = $data[4]) =~ s/ip: //;
    open (FILE, $file)
	or die "Couldn't open $file for reading\n";
    $content = "";
    while (<FILE>) {
	$content .= $_;
    }
    while ($content =~ /\[\[!redirects\s+([^\]\s][^\]]*?)\s*\]\]/ig) {
	push @references, [$updated_at, $page_id, $1]
    }
    debug("Populating page $page_id, $author, $ip");
    $sth->execute($updated_at,$updated_at,$updated_at,$page_id,$content,$author,$ip);
}

# Lastly, the redirects
# INSERT INTO "wiki_references" (created_at, updated_at, page_id, referenced_name, link_type)

my $nreferences = @references;

@cols = qw/
created_at
updated_at
page_id
referenced_name
link_type
/;

$table = "wiki_references";

$sql = "INSERT INTO " . $table . ' (' . join(', ', @cols) . ') VALUES (' . join(', ', map {"?"} @cols ) . ');';

$sth = $dbh->prepare($sql);


for (my $i = 0; $i < $nreferences; $i++ ) {
    my ($created_at, $page_id, $referenced_name) = @{$references[$i]};
    $sth->execute($created_at,$created_at,$page_id,$referenced_name,"R");    
    debug("Redirection: $page_id, $referenced_name");
}

$dbh->disconnect;
exit;

sub debug {
    my ($msg) = @_;
    if ($debug) {
	print STDERR $msg;
    }
}

sub create_db {
    my ($dbh, $wikiname, $lname, $pass, $css) = @_;
    my ($sql,$sth);

    my $creators = q/
CREATE TABLE system ("id" INTEGER PRIMARY KEY NOT NULL, "password" varchar(60) DEFAULT NULL);
CREATE TABLE sessions ("id" INTEGER PRIMARY KEY NOT NULL, "session_id" varchar(255) DEFAULT NULL, "data" text DEFAULT NULL, "updated_at" datetime DEFAULT NULL);
CREATE TABLE wiki_files ("id" INTEGER PRIMARY KEY NOT NULL, "created_at" datetime NOT NULL, "updated_at" datetime NOT NULL, "web_id" integer NOT NULL, "file_name" varchar(255) NOT NULL, "description" varchar(255) NOT NULL);
CREATE TABLE "schema_migrations" ("version" varchar(255) NOT NULL);
INSERT INTO "schema_migrations" VALUES('2');
INSERT INTO "schema_migrations" VALUES('1');
INSERT INTO "schema_migrations" VALUES('20091021024908');
INSERT INTO "schema_migrations" VALUES('20100101192755');
CREATE TABLE "revisions" ("id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, "created_at" datetime NOT NULL, "updated_at" datetime NOT NULL, "revised_at" datetime NOT NULL, "page_id" integer DEFAULT 0 NOT NULL, "content" text(16777215) DEFAULT '' NOT NULL, "author" varchar(60), "ip" varchar(60));
CREATE TABLE "pages" ("id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, "created_at" datetime NOT NULL, "updated_at" datetime NOT NULL, "web_id" integer DEFAULT 0 NOT NULL, "locked_by" varchar(60), "name" varchar(255), "locked_at" datetime);
CREATE TABLE "webs" ("id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, "created_at" datetime NOT NULL, "updated_at" datetime NOT NULL, "name" varchar(60) DEFAULT '' NOT NULL, "address" varchar(60) DEFAULT '' NOT NULL, "password" varchar(60), "additional_style" text(255), "allow_uploads" integer DEFAULT 1, "published" integer DEFAULT 0, "count_pages" integer DEFAULT 0, "markup" varchar(50) DEFAULT 'markdownMML', "color" varchar(6) DEFAULT '008B26', "max_upload_size" integer DEFAULT 100, "safe_mode" integer DEFAULT 0, "brackets_only" integer DEFAULT 0);
CREATE TABLE "wiki_references" ("id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, "created_at" datetime NOT NULL, "updated_at" datetime NOT NULL, "page_id" integer DEFAULT 0 NOT NULL, "referenced_name" varchar(255) DEFAULT '' NOT NULL, "link_type" varchar(1) DEFAULT '' NOT NULL);
DELETE FROM sqlite_sequence;
INSERT INTO "sqlite_sequence" VALUES('webs',1);
INSERT INTO "sqlite_sequence" VALUES('pages',1);
INSERT INTO "sqlite_sequence" VALUES('revisions',1);
CREATE INDEX "index_sessions_on_session_id" ON sessions ("session_id");
CREATE UNIQUE INDEX "unique_schema_migrations" ON "schema_migrations" ("version");
CREATE INDEX "index_revisions_on_page_id" ON "revisions" ("page_id");
CREATE INDEX "index_revisions_on_created_at" ON "revisions" ("created_at");
CREATE INDEX "index_revisions_on_author" ON "revisions" ("author");
CREATE INDEX "index_wiki_references_on_page_id" ON "wiki_references" ("page_id");
CREATE INDEX "index_wiki_references_on_referenced_name" ON "wiki_references" ("referenced_name");
/;

    my @creators = split("\n", $creators);
    my $nc = @creators;
    for my $st (@creators) {
	$dbh->do($st);
    }

    $sql = q{INSERT INTO "system" VALUES(1,?);};
    $sth = $dbh->prepare($sql);
    $pass = $pass || '12rhadlw3r20';
    $sth->execute($pass);

    $sql = q{INSERT INTO "webs" VALUES(1,'2013-02-04 11:42:07','2013-02-04 11:43:54',?,?,?,?,1,1,0,'markdownMML','008B26',100,0,1);};

    $sth = $dbh->prepare($sql);
    my $csstext = "";
    if ($css) {
	open(CSS, $css) or
	    die ("Couldn't open $css\n");
	while (<CSS>) {
	    $csstext .= $_
	}
    }
    $sth->execute($wikiname,$lname,$pass,$csstext);

}
