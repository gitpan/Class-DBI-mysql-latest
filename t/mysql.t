#!/usr/bin/perl -w

use strict;
use Test::Simple tests => 8;
use Class::DBI::mysql;

#-------------------------------------------------------------------------
# Let the testing begin
#-------------------------------------------------------------------------

# Find a test database to use.

my ($dbname, $user, $pass) = ("test", "", "");
my $dbh = DBI->connect("dbi:mysql:$dbname", $user, $pass);

SETUP: while (not $dbh) {
  ($dbname, $user, $pass) = get_db("I cannot connect to a test MySQL database.");
  $dbh = DBI->connect("dbi:mysql:$dbname", $user, $pass);
}

# Find a suitable table to play with, by finding the last table,
# and going beyond it - we can't magically autoincrement in case
# the table name has an underscore in it, so we prepend a z. 
my @tables = sort @{ $dbh->selectcol_arrayref(qq{
  SHOW TABLES
})};
my $table = $tables[-1] || "aaa";
   $table = "z$table";

my $version = get_mysql_version($dbh);
eval {
  my $text = ($version >= 323) ?  " , FULLTEXT(name) " : "";
  my $create = qq{
    CREATE TABLE $table (
      id mediumint not null auto_increment primary key,
      name varchar(50) not null default '',
      val  char(1) default 'A',
      mydate date default '' not null
      $text
    )
  };
  $dbh->do($create);
};
# Uggh.
if ($@) { undef $dbh; warn "I cannot write to that database\n"; goto SETUP; }

$dbh->do(qq{
  INSERT INTO $table (name) VALUES
  ('MySQL has now support'), ( 'for full-text search'),
  ('Full-text indexes'), ( 'are called collections'),
  ('Only MyISAM tables'), ('support collections'),
  ('Function MATCH ... AGAINST()'), ('is used to do a search'),
  ('Full-text search in MySQL'), ( 'implements vector space model')
});


package Foo;
use base 'Class::DBI::mysql';
__PACKAGE__->set_db('Main', "dbi:mysql:$dbname", $user, $pass);
__PACKAGE__->set_up_table($table);

package main;

ok(Foo->can('name'), "We're set up OK");
ok(Foo->count == 10, "We have 10 rows");
my @all = Foo->retrieve_all;
ok(@all == 10,  "And 10 results from retrieve all");

# Test random. Is there a sensible way to test this is actually
# random? For now we'll just ensure that we get something back.
my $obj = Foo->retrieve_random;
ok($obj && $obj->id, "We can retrieve a random row");

# Test setting with CURDATE(). We can't sensibly validate that the
# date/time set is accurate, as the clock on the database server
# may be wildly different from the clock on the local machine,
# but at least we can test that it's set to *something*. 

my $one = $all[0];
my $id  = $one->id;
   $one->mydate("0000-00-00") and $one->commit;
ok($one->mydate eq "0000-00-00", "Date is blank");
   $one->mydate("CURDATE()") and $one->commit;
ok($one->mydate ne "0000-00-00" && index($one->mydate,"-") > -1,
     "Date is no longer blank (object):" . $one->mydate);
   $one = Foo->retrieve($id);
ok($one->mydate ne "0000-00-00" && index($one->mydate,"-") > -1,
     "Date is no longer blank (database):" . $one->mydate);

if ($version >= 323) {
  my @tony = Foo->search_match(name => "MySQL");
  ok(@tony == 2, "Search match OK");
} else {
  ok(1, "Skipping search match (needs 3.23 or higher)");
}


sub get_db {
  my $msg = shift;
  my $old_fh = select(STDERR);
  print "\n$msg\n";
  my $dbname = "";
  while (!$dbname) {
    print "Please specify the name of a writable database: ";
    $dbname    = <STDIN>; chomp $dbname;
  }
  print " A username to access this data source: ";
  my $user = <STDIN>; chomp $user;
  print " And a password: ";
  my $pass = <STDIN>; chomp $pass;
  select($old_fh);
  return ($dbname, $user, $pass);
}

sub get_mysql_version {
  my $dbh = shift;
  my %var = map { $_->[0] => $_->[1] } @{ $dbh->selectall_arrayref(qq{
    SHOW VARIABLES
  })};
  my @version = split /\./, $var{version};
  return sprintf "%01d%02d", $version[0], $version[1];
}

# Clean up after ourselves.
END {
  $dbh->do("DROP TABLE $table");
  $dbh->disconnect;
}

