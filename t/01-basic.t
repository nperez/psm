use Test::More('tests', 7);
use POE;

my $test = 0;

{
    package My::Session;
    use 5.010;
    use Moose;
    with 'POE::Session::Moose';


    sub _start
    {
        my $self = shift(@_);
        Test::More::pass('Start called');
        $self->alias('my_alias'.$test);
        $self->poe()->kernel()->yield('foo');
    }

    sub _stop
    {
        Test::More::pass('Stop called');
    }

    sub foo
    {
        my $self = shift(@_);
        Test::More::pass('foo called');
        if($test == 0)
        {
            $self->poe()->kernel()->state
            (
                'bar',
                sub
                {
                    my $self = shift(@_);
                    Test::More::pass('bar called');
                }
            );
            $test++;
        }
        elsif($test == 1)
        {
            $self->poe()->kernel()->state
            (
                'foo',
                undef
            );

            $self->poe()->kernel()->yield('foo');
            $test++;
        }

        $self->poe()->kernel()->yield('bar');
    }

    1;
}

my $sess = My::Session->new({ options => { 'trace' => 1 }});
my $sess2 = My::Session->new({ options => { 'trace' => 1 }});

POE::Kernel->run();

1;
