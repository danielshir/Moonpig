package Moonpig::Role::HasCollections;
use Moonpig::Util qw(class);
use Moonpig::Types qw(Factory);
use MooseX::Role::Parameterized;
use MooseX::Types::Moose qw(Str HashRef Defined);

=head2 USAGE

	package Foo;
	with (Moonpig::Role::HasCollections => {
	  item => 'banana',
          item_factory => 'Fruit::Banana',
        });

        sub banana_array { ... }   # Should return an array of this object's
                                   # bananas

        sub add_banana { ... }     # Should add a banana to this object

        package main;
        my $foo = Foo->new(...);

        my $bananas = $foo->banana_collection({...});
        $bananas->items;     # same as $foo->banana_array
        $bananas->item_list  # same as @{$foo->banana_array}
        $bananas->n_items;   # number of bananas

        # published methods
        $bananas->all                 # same as item_list
        $bananas->count               # same as n_items
        $bananas->find_by_guid($guid)
        $bananas->find_by_xid($xid)

=cut

requires 'ledger';

# Name of the sort of thing this collection will contain
# e.g., "refund".
parameter item => (isa => Str, required => 1);
# Plural version of above
parameter items => (isa => Str, lazy => 1,
                    default => sub { $_[0]->item . 's' },
                   );

# Class name or factory object for an item in the collection
# e.g., class('Refund')
parameter item_factory => (
  isa => Str, required => 1,
);

# Class name or factory object for the collection itself.
# e.g., "Moonpig::Class::RefundCollection", which will do
#   Moonpig::Role::CollectionType
parameter factory => (
  isa => Factory,
  lazy => 1,
  default => sub {
    my ($p) = @_;
    require Moonpig::Role::CollectionType;
    my $item_factory = $p->item_factory;
    my $item_class = ref($item_factory) || $item_factory;
    my $item_collection_role = Moonpig::Role::CollectionType->meta->
      generate_role(parameters => {
        item_class => $item_class,
        add_item => $p->add_thing,
      });
    my $c = class({ $p->item_collection_name => $item_collection_role});
    return $c;
  },
);

# Name for the item collection class
# e.g., "RefundCollection";
parameter item_collection_name => (
  isa => Str, lazy => 1,
  default => sub {
    my ($p) = @_;
    ucfirst($p->item . "Collection");
  },
);

sub methods {
  my ($x) = @_;
  my $class = ref($x) || $x;
  no strict 'refs';
  my $stash = \%{"$class\::"};
  for my $k (sort keys %$stash) {
    print STDERR "# $k (via $class)\n" if defined &{"$class\::$k"};
  }
  for my $parent (@{"$class\::ISA"}) {
    methods($parent);
  }
}

# Name of ledger method that returns an arrayref of the things
# default "thing_array"
parameter accessor => (isa => Str, lazy => 1,
                       default => sub {
                         $_[0]->item . "_array" },
                      );

# Method name for collection object constructor
# Default: "thing_collection"
parameter constructor => (isa => Str, lazy => 1,
                          default => sub { $_[0]->item . "_collection" },
                         );

# Names of ledger methods
parameter add_thing => (isa => Str, lazy => 1,
                        default => sub { "add_" . $_[0]->item },
                       );

role {
  my ($p) = @_;
  my $thing = $p->item;
  my $things = $p->items;
  my $accessor = $p->accessor || "$thing\_array";
  my $constructor = $p->constructor || "$thing\_collection";
  my $add_thing = $p->add_thing || "add_$thing";
  my $collection_factory = $p->factory;

  # the accessor method is required
  requires $accessor;
  requires $add_thing;

  # build collection constructor
  method $constructor => sub {
    my ($parent, $opts) = @_;
    $p->factory->new({
      items => $parent->$accessor,
      options => $opts,
      ledger => $parent->ledger
    });
  };
};

1;