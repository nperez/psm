{package POEx::Role::SessionInstantiation::Meta::POEState;}

use MooseX::Declare;

#ABSTRACT: A read-only object that provides POE context

class POEx::Role::SessionInstantiation::Meta::POEState
{
    use POEx::Types(':all');
    use MooseX::Types::Moose('Maybe', 'Str');

=attr sender is: ro, isa: Kernel|Session|DoesSessionInstantiation

The sender of the current event can be access from here. Semantically the same
as $_[+SENDER].

=cut

    has sender  => ( is => 'ro', isa => Kernel|Session|DoesSessionInstantiation);
    
=attr state is: ro, isa => Str

The state fired. This should match the current method name (unless of course
within the _default event handler, then it will be the event name that was 
invoked but did not exist in your object instance.

=cut
    has state   => ( is => 'ro', isa => Str );

=attr kernel is: ro, isa: Kernel

This is actually the POE::Kernel singleton provided as a little sugar instead
of requiring use of $poe_kernel, etc. To make sure you are currently within a 
POE context, check this attribute for definedness.

=cut

    has kernel  => ( is => 'ro', isa => Kernel );

=attr [qw/file line from/] is: rw, isa: Maybe[Str]

These attributes provide tracing information from within POE. From is actually
not used in POE::Session as far as I can tell, but it is available just in 
case.

=cut

    has file    => ( is => 'ro', isa => Maybe[Str] );
    has line    => ( is => 'ro', isa => Maybe[Str] );
    has from    => ( is => 'ro', isa => Maybe[Str] );

=method clone

Clones the current POEState object and returns it

=cut

    method clone
    {
        return $self->meta->clone_object($self);
    }
}

1;

__END__

