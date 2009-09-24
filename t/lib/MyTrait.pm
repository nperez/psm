{package MyTrait;}
use MooseX::Declare;

role MyTrait(Str :$attr = 'blarg')
{
    use Test::More;
    use aliased 'POEx::Role::Event';
    use MooseX::Types::Moose('Int');
    
    with 'POEx::Role::SessionInstantiation::Meta::Session::Events';

    has $attr => ( is => 'rw', isa => Int );

    after _start is Event
    {
        $self->$attr(1);
        pass("Trait start called and attribute($attr) set");
    }
}
1;
__END__
