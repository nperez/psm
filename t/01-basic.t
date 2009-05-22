use Test::More('tests', 13);
use POE;
use MooseX::Declare;

my $test = 0;

class My::Session with POEx::Role::SessionInstantiation
{
    use 5.010;
    use aliased 'POEx::Role::Event';

    method _start(Str $alias) is Event
    {
        Test::More::pass('Start called');
        $self->alias($alias);
        $self->yield('foo');
    }

    method _stop is Event
    {
        Test::More::pass('Stop called');
    }

    method foo is Event
    {
        Test::More::pass('foo called');
        if($test == 0)
        {
            $self->poe()->kernel()->state
            (
                'bar',
                method
                {
                    Test::More::pass('bar called');
                    
                    class Foo with POEx::Role::SessionInstantiation 
                    { 
                        use aliased 'POEx::Role::Event'; 
                        after _start is Event 
                        { 
                            Test::More::pass('after _start called'); 
                        } 
                        method blat is Event 
                        { 
                            Test::More::pass('blat called'); 
                        } 
                    }

                    Foo->new( options => { 'trace' => 1 }, alias => 'blat_alias' );
                    $self->post('blat_alias', 'blat');
                    
                    class Bar with POEx::Role::SessionInstantiation 
                    { 
                        use aliased 'POEx::Role::Event'; 
                        method flarg is Event 
                        { 
                            Test::More::pass('flarg called'); 
                        } 
                        before _stop is Event
                        {
                            Test::More::pass('before _stop called');
                        }
                    }

                    Bar->new( options => { 'trace' => 1 }, alias => 'flarg_alias' );
                    $self->post('flarg_alias', 'flarg');
                }
            );
            $test++;
        }
        elsif($test == 1)
        {   
            # remove foo from test1
            $self->poe()->kernel()->state
            (
                'foo',
                undef
            );
            
            # post an event to non-existent foo
            $self->yield('foo');
            $test++;
        }
        
        # only test0 should have this event
        $self->yield('bar');
    }

    method _default(@args) is Event
    {
        given($self->poe->state)
        {
            when('foo') { Test::More::pass('default redirect foo'); }
            when('bar') { Test::More::pass('default redirect bar'); }
        }
    }

    1;
}

my $sess = My::Session->new( options => { 'trace' => 1 }, args => [ 'test0' ]);
my $sess2 = My::Session->new( options => { 'trace' => 1 }, args => [ 'test1' ]);

POE::Kernel->run();

1;
