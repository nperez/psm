use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'POE::Session::Moose',
    license             => 'gpl',
    dist_author         => 'Nicholas R. Perez <nperez@cpan.org>',
    dist_version_from   => 'lib/POE/Session/Moose.pm',
    create_readme       => 1,
    meta => 
    {
        resources =>
        {
            repository => 'http://github.com/'
        }
    },
    build_requires => 
    {
        'Test::More'    => 0,
        'POE'           => 1.004,
        'Moose'         => 0.75
    },
    add_to_cleanup      => [ 'POE-Session-Moose-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
