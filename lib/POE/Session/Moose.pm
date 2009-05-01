package POE::Session::Moose;
use 5.010;
use Moose::Role;
use MooseX::Declare;
use Moose::Util::TypeConstraints;
use POE;

our $VERSION = '0.01';

use overload '""' => sub
{ 
    my $s = shift;
    return $s->orig if $s->orig; 
    return $s; 
};

use overload '!=' => sub
{
    return "$_[0]" ne "$_[1]";
};

use overload '==' => sub
{
    return "$_[0]" eq "$_[1]";
};

has orig => ( is => 'rw', isa =>'Str');

requires '_start';
requires '_stop';

subtype Kernel 
    => as 'POE::Kernel';

subtype Session
    => as 'POE::Session';

subtype CanDoSession
    => as 'Object',
    => where { $_->does('POE::Session::Moose') };

has heap =>
(
    is => 'rw',
    isa => 'Any'
);

has options =>
(
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
    lazy => 1,
);

has poe =>
(
    is => 'ro',
    isa => 'Object',
    default => sub
    {
        my $class = class 
        {
            has sender  => ( is => 'rw', isa => 'Kernel | Session | CanDoSession'  );
            has state   => ( is => 'rw', isa => 'Str' );
            has file    => ( is => 'rw', isa => 'Str | Undef' );
            has line    => ( is => 'rw', isa => 'Str | Undef' );
            has from    => ( is => 'rw', isa => 'Str | Undef' );
            has kernel  => ( is => 'rw', isa => 'Kernel' );
        };

        $class->new_object({});
    },
    lazy => 1
);

has args =>
(
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [] },
    lazy => 1
);

has alias =>
(
    is => 'rw',
    isa => 'Str',
    trigger => sub { shift; $POE::Kernel::poe_kernel->alias_set(shift); },
    clearer => '_clear_alias',
);

has ID =>
(
    is => 'ro',
    isa => 'Int',
    default => sub { $POE::Kernel::poe_kernel->ID_session_to_id(shift) },
    lazy => 1,
);

has _self_meta =>
(
    is => 'rw',
    isa => 'Class::MOP::Class'
);

sub BUILD { 1; }

after 'BUILD' => sub
{
    my $self = shift(@_);
    # This is to enable overload in the consumer class
    {
        no strict 'refs';
        no warnings 'redefine';
        $ {$self->meta->name . "::OVERLOAD"}{dummy}++;
        *{$self->meta->name . "::()"} = sub {};
    }

    #this registers us with the POE::Kernel
    $POE::Kernel::poe_kernel->session_alloc($self, $self->args());

    if($self->options()->{'trace'})
    {
        $self = $self->_clone_self();
        my $meta = $self->meta();
        #warn "BUILD: \n".$meta->dump(2);
        foreach my $name ($meta->get_all_method_names)
        {
            # This is a hack, there has to be a better moose idiom for this
            if ($meta->has_attribute($name))
            {
                next;
            }
            if ($name =~ /BUILD|DOES|_invoke_state|clear_alias|_register_state|meta|does|new|DESTROY|DEMOLISHALL|_clone_self|\(/)
            {
                next;
            }
            my $meta_name = $meta->name;
            #warn "METHOD: $meta_name => $self -> $name";
            $meta->add_around_method_modifier
            (
                $name, 
                sub
                {
                    my ($orig, $self, @etc) = @_;

                    my $poe = $self->poe();
                    my $state = $poe->state();
                    my $file = $poe->file();
                    my $line = $poe->line();
                    
                    POE::Kernel::_warn($self->ID(), " -> $state (from $file at $line)\n" );
                    
                    return $orig->($self, @etc);
                }
            );
        }
    }
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
    my $sender  = shift(@_); 
    my $state   = shift(@_);
    my $etc     = shift(@_); 
    my $file    = shift(@_); 
    my $line    = shift(@_); 
    my $from    = shift(@_);

    my $method = $self->meta()->find_method_by_name($state);

    if(defined($method))
    {
        my $poe = $self->poe();
        $poe->sender($sender);
        $poe->state($state);
        $poe->file($file);
        $poe->line($line);
        $poe->from($from);
        $poe->kernel($POE::Kernel::poe_kernel);
        
        return $method->execute($self, @$etc);
    }
    else
    {
        my $default = $self->meta()->find_method_by_name('default');
        
        if(defined($default))
        {
            my $poe = $self->poe();
            $poe->sender($sender);
            $poe->state($state);
            $poe->file($file);
            $poe->line($line);
            $poe->from($from);
            $poe->kernel($POE::Kernel::poe_kernel);
            
            return $default->execute($self, $state, @$etc);
        }
        else
        {
            my $loggable_self = $POE::Kernel::poe_kernel->_data_alias_loggable($self);
            #warn $self->meta()->dump(2);
            POE::Kernel::_warn
            (
                "a '$state' event was sent from $file at $line to $loggable_self ",
                "but $loggable_self has neither a handler for it ",
                "nor one for _default\n"
            );
        }
    }
}

sub _register_state
{
    #warn "REGISTER STATE";
    # only support inline state usage
    my ($self, $method_name, $coderef) = @_;
    
    confess ('$method_name undefined!') unless $method_name;
    
    $self = $self->_clone_self();

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
            $self->meta()->remove_method($method_name);
        }

        my $new_method = Class::MOP::Method->wrap
        (
            $coderef, 
            (
                name => $method_name,
                package_name => ref($self)
            )
        );

        $self->meta()->add_method($method_name, $new_method);

        if($self->options()->{'trace'})
        {
            my $meta = $self->meta();
            $meta->add_around_method_modifier
            (
                $method_name, 
                sub
                {
                    my ($orig, $self, @etc) = @_;

                    my $poe = $self->poe();
                    my $state = $poe->state();
                    my $file = $poe->file();
                    my $line = $poe->line();
                    
                    POE::Kernel::_warn($self->ID(), " -> $state (from $file at $line)\n" );
                    
                    return $orig->($self, @etc);
                }
            );
        }
    }
}

sub _clone_self
{
    use Data::Dumper;
    my $self = shift;
    
    my $meta = $self->meta();
    #warn Dumper($meta->get_all_methods);
    #warn Dumper({ map { $_->name => $_->body  } $meta->get_all_methods });
    my $anon = Moose::Meta::Class->create_anon_class
    (   
        superclasses => [ $meta->superclasses() ],
        methods => { map { $_->name,  $_->body  } $meta->get_all_methods },
        attributes => [ $meta->get_all_attributes() ],
        roles => [ map { $_->name } $meta->calculate_all_roles() ] ,
    );

    my $orig = "$self";
    {
        no strict 'refs';
        no warnings 'redefine';
        ${$anon->name . "::OVERLOAD"}{dummy}++;
        *{$anon->name . "::()"} = sub {};
    }
    bless($self, $anon->name);
    
    if($orig !~ /__ANON__/)
    {
        $self->orig($orig);
    }

    $self->_self_meta($anon);

    $POE::Kernel::poe_kernel->[POE::Kernel::KR_SESSIONS]->{$orig}->[POE::Kernel::SS_SESSION] = $self;
    
    return $self;
 
}

no Moose::Role;

1;
