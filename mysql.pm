package Class::DBI::mysql;

=head1 NAME

Class::DBI::mysql - Extensions to Class::DBI for MySQL

=head1 SYNOPSIS

  package Film.pm;
  use base 'Class::DBI::mysql';
  __PACKAGE__->set_db('Main', 'dbi:mysql', 'user', 'password');
  __PACKAGE__->set_up_table("film");

  # Somewhere else ...

  $howmany = Film->count;

  @all_films = Film->retrieve_all;
  $tonights_viewing  = Film->retrieve_random;

  @results = Film->search_match($key => $value);

=head1 DESCRIPTION

This is an extension to Class::DBI, containing several functions and
optimisations for the MySQL database. Instead of setting Class::DBI
as your base class, use this instead.

=cut

use strict;
use base 'Class::DBI';

use vars qw($VERSION);
$VERSION = '0.04';

use constant TRUE       => (1==1);
use constant FALSE      => !TRUE;
use constant SUCCESS    => TRUE;
use constant FAILURE    => FALSE;
use constant YES        => TRUE;
use constant NO         => FALSE;

sub _die { require Carp; Carp::croak(@_); } 

=head2 set_up_table

  __PACKAGE__->set_up_table("table_name");

Traditionally, to use Class::DBI, you have to set up the columns:

  __PACKAGE__->columns(All => qw/list of columns/);
  __PACKAGE__->columns(Primary => 'column_name');

Whilst this allows for more flexibility if you're going to arrange your
columns into a variety of groupings, sometimes you just want to create the
'all columns' list. Well, this information is really simple to extract
from MySQL itself, so why not just use that?

This call will extract the list of all the columns, and the primary key
and set them up for you. It will die horribly if the table contains
no primary key, or has a composite primary key.

=cut

sub set_up_table {
  my $class = shift;
  my $table = shift;
  my $ref = $class->db_Main->selectall_arrayref("DESCRIBE $table");
  my (@cols, $primary);
  foreach my $row (@$ref) {
    push @cols, $row->[0];
    next unless ($row->[3] eq "PRI");
    _die "$table has composite primary key" if $primary;
    $primary = $row->[0];
  }
  _die "$table has no primary key" unless $primary;
  $class->table($table);
  $class->columns(All => @cols);
  $class->columns(Primary => $primary);
}

=head2 count

  $howmany = Film->count;

This will count how many of these there are. You could get the
same effect by doing a 'select all', but this avoids the overhead
of having to fetch them all back by using MySQL's highly optimised
COUNT(*) function instead.

=cut

__PACKAGE__->set_sql('countem', <<"");
SELECT COUNT(*)
FROM   %s

sub count {
    my($proto) = @_;
    my($class) = ref $proto || $proto;
    my $data;
    eval {
        my $sth = $class->sql_countem($class->table);
        $sth->execute();
        $data = $sth->fetchrow_array;
        $sth->finish;
    };
    if ($@) {
      print "EEEK: $@\n";
        $class->DBIwarn('countem');
        return;
    }
    return $data;
}

=head2 retrieve_all

  @films = Film->retrieve_all;

This will return you a list of objects - one for each of the rows in your
table. 

=cut

__PACKAGE__->set_sql('RetrieveAllRecs', <<"");
SELECT %s
FROM   %s

sub retrieve_all {
    my($proto) = @_;
    my($class) = ref $proto || $proto;

    my $sth;
    eval {
        $sth = $class->sql_RetrieveAllRecs(join(', ', $class->columns('Essential')),
                              $class->table);
        $sth->execute();
    };
    if($@) {
        $class->DBIwarn("Retrieve All");
        return;
    }

    return map $class->construct($_), $sth->fetchall_hash;
} 

=pod

=head2 retrieve_random

  my $film = Film->retrieve_random;

This will select a random row from the database, and return you
the relevant object.

(MySQL 3.23 and higher only, at this point)

=cut

__PACKAGE__->set_sql('GetRandom', <<"");
SELECT %s
FROM   %s
ORDER BY RAND()
LIMIT 1

sub retrieve_random {
    my($proto) = @_;
    my($class) = ref $proto || $proto;
    my $data;
    eval {
        my $sth = $class->sql_GetRandom(join(', ', $class->columns('Essential')),
                                    $class->table,
                                   );
        $sth->execute();
        $data = $sth->fetchrow_hashref;
        $sth->finish;
    };
    if ($@) {
      print "EEEK: $@\n";
        $class->DBIwarn('GetRandom');
        return;
    }
    return unless defined $data;
    return $class->construct($data);
}

=head2 search_match

  @results = Film->search_match($key => $value);

This is like search, but using the MySQL 'full text matching' capabilities.

=cut

__PACKAGE__->set_sql('search_match', <<"");
SELECT %s
FROM   %s
WHERE  MATCH %s AGAINST (?)

sub search_match {
    my($proto, $key, $value) = @_;
    my($class) = ref $proto || $proto;

    $class->normalize_one(\$key);

    _die "$key is not a column" unless ($class->is_column($key));

    my $sth;
    eval {
        $sth = $class->sql_search_match(join(', ', $class->columns('Essential')),
                              $class->table,
                              $key); 
        $sth->execute($value);
    };
        
    if($@) {
        $class->DBIwarn("'$key' -> '$value'", 'Search');
        return;
    }

    return map { $class->construct($_) } $sth->fetchall_hash;
} 

=head1 CURDATE() / CURTIME() / NOW()

Due to the way in which placeholders work under DBI, it's currently very
difficult to translate a query like the following to Class::DBI

  UPDATE foo
     SET flibble = "bar", since = CURDATE()

Rather than having to convert all your columns to timestamps, this module
allows you to specify CURDATE(), CURTIME() or NOW() as values:
  
  $foo->flibble("bar") and $foo->since("CURDATE()") and $foo->commit;

CAVEAT: Note that until you've called 'commit', the value of this
field will be set to this B<string>, and not the translation of it. For
objects which are going to make use of this feature, consider turning
autocommit on.

=cut

__PACKAGE__->set_sql('commitall', <<"", 'Main');
UPDATE %s
SET    %s
WHERE  %s = ?

sub commit {
  my $self = shift;

  if( my @changed_cols = $self->is_changed ) {
    my($primary_col) = $self->columns('Primary');
    eval {
      my (@cols, @vals, @magic);
      foreach (@changed_cols) {
        if ($self->{$_} eq "CURDATE()" or $self->{$_} eq "CURTIME()" or $self->{$_} eq "NOW()") {
          push @cols, "$_ = $self->{$_}";
          delete $self->{$_}; # so we reload it fresh next time.
          next;
        } 
        push @cols, "$_ = ?";
        push @vals, $self->{$_};
      }
      my $set = join( ', ', @cols);
      my $sth = $self->sql_commitall($self->table, $set, $primary_col);
      $sth->execute(@vals, $self->id );
    };
    if($@) {
      $self->DBIwarn( $primary_col, 'commitall' );
      return;
    }
    $self->{__Changed}  = {};
  }
  return SUCCESS;
}

=head1 COPYRIGHT

Copyright (C) 2001 Tony Bowden. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Tony Bowden, E<lt>tony@tmtm.comE<gt>.

=head1 SEE ALSO

L<Class::DBI>. MySQL (http://www.mysql.com/)

=cut

1;
