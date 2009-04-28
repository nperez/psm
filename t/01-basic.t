use Test::More('tests', 3);
use POE;

{
    package My::Session;
    use 5.010;
    use Moose;
    with 'POE::Session::Moose';

    sub BUILD { 1; }
    
    sub _start
    {
        my $self = shift(@_);
        Test::More::pass('Start called');
        $self->alias('my_alias');
        $self->poe->{'kernel'}->yield('foo');
    }

    sub _stop
    {
        Test::More::pass('Stop called');
    }

    sub foo
    {
        my $self = shift(@_);
        Test::More::pass('foo called');
    }

    1;
}

my $sess = My::Session->new();

POE::Kernel->run();

1;
