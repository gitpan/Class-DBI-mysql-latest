use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Class::DBI::mysql',
    'VERSION_FROM'	=> 'mysql.pm', # finds $VERSION
    'PREREQ_PM'		=> { 
                             'Class::DBI' => 0.14, 
                             'Test::Simple' => 0.01, 
                           },
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'mysql.pm', # retrieve abstract from module
       AUTHOR     => 'Tony Bowden <tony@tmtm.com>') : ()),
);
