package Bugzilla::Extension::PatchReport;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Extension::PatchReport::Util;

our $VERSION = '';

sub page_before_template {
    my ($self, $args) = @_;
    
    page(%{ $args });
    
}


__PACKAGE__->NAME;
