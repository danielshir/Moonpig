package Moonpig::Role::Consumer::PredictsExpiration;
use Moose::Role;
# ABSTRACT: a consumer that can predict when it will expire

use namespace::autoclean;

require Stick::Publisher;
Stick::Publisher->VERSION(0.20110324);
use Stick::Publisher::Publish 0.20110324;

use List::AllUtils qw(any);
use Moonpig::Util qw(sumof);

use Moonpig::Behavior::Packable;

requires 'estimated_lifetime'; # TimeInterval, from created to predicted exp
requires 'expiration_date';    # Time, predicted exp date
requires 'remaining_life';     # TimeInterval, from now to predicted exp

publish replacement_chain_expiration_date => {} => sub {
  my ($self) = @_;

  my @chain = $self->replacement_chain;
  if (any {! $_->does('Moonpig::Role::Consumer::PredictsExpiration')} @chain) {
    Moonpig::X->throw("replacement in chain cannot predict expiration");
  }

  return($self->expiration_date + (sumof { $_->estimated_lifetime } @chain));
};

PARTIAL_PACK {
  return {
    replacement_chain_expiration_date => $_[0]->replacement_chain_expiration_date,
  };
};

1;
