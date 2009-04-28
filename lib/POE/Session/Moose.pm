package POE::Session::Moose;
use 5.010;
use Moose::Role;

our $VERSION = '0.01';

requires '_start';
requires '_stop';

has heap =>
(
    is => 'rw',
    isa => 'Any'
);

has options =>
(
    is => 'rw',
    isa => 'HashRef'
);

has poe =>
(
    is => 'ro',
    isa => 'HashRef',
    writer => '_set_state_info'
);

has args =>
(
    is => 'rw',
    isa => 'ArrayRef'
);

has alias =>
(
    is => 'rw',
    isa => 'Str',
    trigger => sub { shift; $POE::Kernel::poe_kernel->alias_set(shift); },
    clearer => '_clear_alias',
);

sub BUILD { 1; }

after 'BUILD' => sub
{
    my $self = shift(@_);
    $POE::Kernel::poe_kernel->session_alloc($self, $self->args());
};

sub clear_alias
{
    my $self = shift(@_);
    $POE::Kernel::poe_kernel->alias_remove($self->alias());
    $self->_clear_alias();
}

sub _invoke_state
{
    my $self    = shift(@_);
    my $source  = shift(@_); 
    my $state   = shift(@_);
    my $etc     = shift(@_); 
    my $file    = shift(@_); 
    my $line    = shift(@_); 
    my $from    = shift(@_);

    my $method = $self->meta()->find_method_by_name($state);

    if(defined($method))
    {
        $self->_set_state_info
        (
            {
                'source'    => $source,
                'state'     => $state,
                'file'      => $file,
                'line'      => $line,
                'from'      => $from,
                'kernel'    => $POE::Kernel::poe_kernel,
            }
        );
        
        return $method->execute($self, @$etc);
    }
    else
    {
        my $default = $self->meta()->find_method_by_name('default');
        
        if(defined($default))
        {
            # XXX Debug logging
            $default->execute($self, $state, @$etc);
        }
        else
        {
            # XXX Debug logging
        }
    }
}

sub _register_state
{
    # only support inline state usage
    my ($self, $method_name, $coderef) = @_;
    
    # XXX Assert $method_name 

    if(!defined($coderef))
    {
        # we mean to remove this method
        $self->meta()->remove_method($method_name);
    }
    else
    {
        my $method = $self->meta()->find_method_by_name($method_name);
        
        if(defined($method))
        {
            my $new_method = Class::MOP::Method->wrap
            (
                $coderef, 
                (
                    name => $method_name,
                    package_name => $method->package_name()
                )
            );
            
            $self->meta()->remove_method($method_name);
            $self->meta()->add_method($method_name, $new_method);
        }
        else
        {
            # XXX Debug logging
        }
    }

}

sub ID
{
    $POE::Kernel::poe_kernel->ID_session_to_id(shift);
}

no Moose::Role;

1;
