package POEx::Role::SessionInstantiation::Meta::Session::Sugar;

#ABSTRACT: Provides some convenience methods for some POE::Kernel methods

use MooseX::Declare;

role POEx::Role::SessionInstantiation::Meta::Session::Sugar
{
    use POEx::Types(':all');

=method_public [qw/post yield call/]

These are provided as sugar for the respective POE::Kernel methods.

=cut
    
    method post(SessionAlias|SessionID|Session|DoesSessionInstantiation $session, Str $event_name, @args) 
    {
        confess('No POE context') if not defined($self->poe->kernel);
        return $self->poe->kernel->post($session, $event_name, @args);
    }

    method yield(Str $event_name, @args)
    {
        confess('No POE context') if not defined($self->poe->kernel);
        return $self->poe->kernel->yield($event_name, @args);
    }

    method call(SessionAlias|SessionID|Session|DoesSessionInstantiation $session, Str $event_name, @args) 
    {
        confess('No POE context') if not defined($self->poe->kernel);
        return $self->poe->kernel->call($session, $event_name, @args);
    }
}

1;
__END__
