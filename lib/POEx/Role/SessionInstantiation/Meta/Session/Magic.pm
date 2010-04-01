package POEx::Role::SessionInstantiation::Meta::Session::Magic;

use MooseX::Declare;

#ABSTRACT: Provides the magic necessary to integrate with POE

role POEx::Role::SessionInstantiation::Meta::Session::Magic
{
    use POE;
    use MooseX::Types::Moose(':all');

=method_private overload "", !=, ==

Stringification, and numeric comparison are overriden so that we can fool POE
into thinking that our inject reference is actually the same as the old 
reference.

The numeric comparisons actually use string comparisons and stringifies the 
provided arguments.

=cut
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

=attribute_private orig

    is: rw, isa: Str

orig stores the stringification of the original reference. This lets us
fool POE into thinking that our new reference is the old reference.

=cut

    has orig => ( is => 'rw', isa => Str );

=attribute_private orig_name

    is: rw, isa: Str

This stores the original meta name that would otherwise be lost

=cut

    has orig_name => ( is => 'rw', isa => Str );

=attribute_private _self_meta

    is: rw, isa: Str

This is where we store the newly created anonymous clone class to keep it from
going out of scope

=cut

    has _self_meta =>
    (
        is => 'rw',
        isa => 'Class::MOP::Class'
    );
    
    sub BUILD { 1 }

=method_private after BUILD

All of the magic for turning the constructed object into a Session happens in 
this method. If a BUILD is not provided, a stub exists to make sure this advice
is executed. Internally, it delegates actual execution to _post_build to allow
it to be advised.

=cut
    after BUILD { $self->_post_build() }

=method_private _post_build

_post_build does the magic of making sure our overload magic is activated and
that we are registered with POE via $poe_kernel->session_alloc.

=cut

    method _post_build
    {
        $self->_overload_magic();
        $self->_poe_register();
    }

=method_private _overload_magic

To active the overload magic, use this method. This is what _post_build uses.

=cut

    method _overload_magic
    {
        #enable overload in the composed class (ripped from overload.pm)
        {
            no strict 'refs';
            no warnings 'redefine';
            ${$self->meta->name . "::OVERLOAD"}{dummy}++;
            *{$self->meta->name . "::()"} = sub {};
        }

        # we need a no-op bless here to activate the magic for overload
        bless ({}, $self->meta->name);
        
    }

=method_private _poe_register

To register this instance with POE, use this method. This is what _post_build
uses.

=cut

    method _poe_register
    {
        #this registers us with the POE::Kernel
        $POE::Kernel::poe_kernel->session_alloc($self, @{$self->args()})
            if not $self->orig;
    }

=method_private _clone_self

_clone_self does the initial anonymous class clone as needed to enable per
instance modification via normal POE mechanisms.

=cut

    method _clone_self
    {
        # we only need to clone once
        if($self->orig)
        {
            return $self;
        }

        # we need to hold on to the original stringification
        my $orig = "$self";
        $self->orig($orig);

        my $meta = $self->meta();

        $self->orig_name($meta->name);

        my $anon = Moose::Meta::Class->create_anon_class
        (   
            superclasses => [ $meta->superclasses() ],
            methods => { map { $_->name,  $_  } $meta->get_all_methods },
            attributes => [ $meta->get_all_attributes() ],
        );
        
        $anon->add_role($_) for @{$meta->roles};
        
        #enable overload in the anonymous class (ripped from overload.pm)
        {
            no strict 'refs';
            no warnings 'redefine';
            ${$anon->name . "::OVERLOAD"}{dummy}++;
            *{$anon->name . "::()"} = sub {};
        }
        
        my $stuff;
        # need to copy all of the symbols over
        foreach my $type (keys %{ $stuff = { SCALAR => '$', ARRAY => '@', HASH => '%', CODE => '&' } } )
        {
            my $symbols = $meta->get_all_package_symbols($type);
            foreach my $key (keys %$symbols)
            {
                if(!$anon->has_package_symbol($stuff->{$type} . $key))
                {
                    if($type eq 'SCALAR')
                    {
                        $anon->add_package_symbol($stuff->{$type} . $key, ${$symbols->{$key}});
                    }
                    else
                    {
                        $anon->add_package_symbol($stuff->{$type} . $key, $symbols->{$key});
                    }

                }
            }
        }
        # this bless not only reblesses into the anonymous class, but also activates overload
        bless($self, $anon->name);

        # and to keep our anonymous class from going out of scope, stash a reference into ourselves
        $self->_self_meta($anon);

        # And here is where we break POE encapsulation
        $POE::Kernel::poe_kernel->[POE::Kernel::KR_SESSIONS]->{$orig}->[POE::Kernel::SS_SESSION] = $self;

        return $self;
    }
}
