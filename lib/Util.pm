# (c) Copyright Elijah Newren 2005
# (c) Copyright Frederic Peters 2009
# Licensed under whatever Free/Open Source license is necessary to
# allow this to be in upstream bugzilla (if they want my ugly hacks)
# and be the most useful to the Gnome Bugsquad (is there a "please
# bury this code deep beneath the Ocean's bed and pretend one of our
# people never wrote it" license?).  I give permission to the Gnome
# Foundation board of directors to declare what that means.
#
# Sucks to be you to have to work to figure out the license, doesn't
# it?  Well, better you than me.  ;-)

package Bugzilla::Extension::PatchReport::Util;

use strict;
use base qw(Exporter);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Util;
use Bugzilla::User;

our @EXPORT = qw(
    page
);

sub page {
    my %params = @_;
    my ($vars, $page) = @params{qw(vars page_id)};
    if ($page =~ /^patchreport\./) {
        _page_patch_report($vars);
    }
}

sub _page_patch_report {
    my $vars = shift;

    my $cgi = Bugzilla->cgi;
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->user;

    my $quoted_product="'%'";   # (string) which product to search, % for all
    my $quoted_component="'%'"; # (string) which component to search, % for all
    my $patch_status="none";  # (string) status of patches to search for
    my $min_days = -1;    # (int) Don't show patches younger than this (in days)
    my $max_days = -1;    # (int) Don't show patches older than this (in days)
    my $submitter;        # (int) submitter id

    if (!$dbh->bz_column_info('attachments', 'status')) {
        ThrowCodeError('patchreport_no_attachments_status')
    }

    my @products = $cgi->param('product');
    my @components = $cgi->param('component');

    @products = grep { defined $_ && $_ ne "" } @products;
    @components = grep { defined $_ && $_ ne "" } @components;

    if (scalar @products) {
        $quoted_product = join(',', map($dbh->quote($_), @products));
    }
    if (scalar @components) {
        $quoted_component = join(',', map($dbh->quote($_), @components));
    }

    if (defined $cgi->param('patch-status') && $cgi->param('patch-status') ne ""){
        $patch_status = $cgi->param('patch-status');
    }
    if (defined $cgi->param('min_days') && $cgi->param('min_days') ne ""){
        $min_days = $cgi->param('min_days');
        detaint_natural($min_days) || die "min_days parameter must be a number";
    }
    if (defined $cgi->param('max_days') && $cgi->param('max_days') ne ""){
        $max_days = $cgi->param('max_days');
        detaint_natural($max_days) || die "max_days parameter must be a number";
    }
    if (defined $cgi->param('submitter') && $cgi->param('submitter') ne "") {
        $submitter = login_to_id($cgi->param('submitter'));
        unless ($submitter > 0) {
            ThrowUserError('invalid_username', { name => $cgi->param('submitter') });
        }
    }

    # Determine the report type...
    my $type;
    if ($patch_status eq "none") {
        $type = "Unreviewed";
    }
    elsif ($patch_status eq "obsolete") {
        $type = "Obsolete";
    }
    else {
        trick_taint($patch_status);
        $type = $dbh->selectrow_array(
                    "SELECT value
                       FROM attachment_status
                       WHERE attachment_status.value = ?",
                       undef, $patch_status);
    }

    #
    # Then collect the needed information
    #
    my $stats = get_unreviewed_patches_and_stats($quoted_product,
                                                 $quoted_component,
                                                 $patch_status,
                                                 $min_days,
                                                 $max_days,
                                                 $submitter);

    #
    # Finally, print it all out
    #
    $vars->{'patch_type'} = $type;
    $vars->{'stats'} = $stats;
}


sub get_unreviewed_patches_and_stats {
    my ($quoted_product, $quoted_component, $patch_status,
        $min_days, $max_days, $submitter) = (@_);

    my $query;
    my $dbh = Bugzilla->dbh;

    $query = " SELECT attachments.attach_id, attachments.bug_id,
                      (" . $dbh->sql_to_days('LOCALTIMESTAMP(0)') . "-" .
                       $dbh->sql_to_days('attachments.creation_ts') . ") AS age,
                      substring(attachments.description, 1, 70),
                      products.name AS product, components.name AS component
                 FROM attachments
           INNER JOIN bugs
                   ON attachments.bug_id = bugs.bug_id
           INNER JOIN products
                   ON bugs.product_id = products.id
           INNER JOIN components
                   ON bugs.component_id = components.id
                WHERE attachments.ispatch = '1'";

    if ($quoted_product && $quoted_product ne "'%'") {
      trick_taint($quoted_product);
      $query .= " AND products.name IN ($quoted_product)";
    }
    if ($quoted_component && $quoted_component ne "'%'") {
      trick_taint($quoted_component);
      $query .= " AND components.name IN ($quoted_component)";
    }
    if ($submitter) {
      # $submitter is a numeric
      $query .= " AND attachments.submitter_id = $submitter";
    }
    if ($min_days && $min_days != -1) {
      $query .= " AND attachments.creation_ts <= LOCALTIMESTAMP(0) - " .
          $dbh->sql_interval($min_days, 'DAY');
    }
    if ($max_days && $max_days != -1) {
      $query .= " AND attachments.creation_ts >= LOCALTIMESTAMP(0) - " .
          $dbh->sql_interval($max_days, 'DAY');
    }
    if ($patch_status eq 'obsolete') {
      $query .= " AND attachments.isobsolete  = '1'";
    } else {
      $query .= " AND attachments.isobsolete != '1'";
    }
    if ($patch_status ne 'obsolete') {
        $query .= " AND attachments.status = '" . $patch_status . "'";
    }
    $query .= "   AND (bugs.bug_status = 'UNCONFIRMED'
                       OR bugs.bug_status = 'NEW'
                       OR bugs.bug_status = 'ASSIGNED'
                       OR bugs.bug_status = 'REOPENED')
             ORDER BY products.name, components.name, attachments.bug_id, attachments.attach_id";
    open(BLABLABLA, ">/tmp/foobar") || die "Crap!\n";
    print BLABLABLA "hello world\n" . $query . "\n";


    my $sth = $dbh->prepare($query);
    $sth->execute();

    $query = "SELECT substring(short_desc, 1, 70), priority, bug_severity
                FROM bugs
               WHERE bug_id = ?";

    my $sth_Buginfo = $dbh->prepare($query);

    my ($cur_product, $cur_component, $cur_bug) = ('', '', 0);
    my ($prod_list, $comp_list, $bug_list, $patch_list) = ([], [], [], []);
    my ($new_product, $new_component);
    my ($total_count, $prod_count, $comp_count) = (0, 0, 0);
    my $stats = {
        'count' => 0,
        'product_list' => []
    };

    $prod_list = $stats->{product_list};
    while (my ($attach_id, $bug_id, $age, $desc, $prod, $comp) = $sth->fetchrow_array) {

        # Check if we've moved on to a new product
        if ($cur_product ne $prod) {
            if ($cur_product ne '') {
                $new_product->{count} = $prod_count;
                $prod_count = 0;
                $new_component->{count} = $comp_count;
                $comp_count = 0;
            }

            $cur_product = $prod;
            $new_product = {
                'name' => $prod,
                'component_list' => []
            };

            push @{$prod_list}, $new_product;
            $cur_component = '';
            $comp_list = $new_product->{component_list};
        }

        # Check if we've moved on to a new component
        if ($cur_component ne $comp) {
            if ($cur_component ne '') {
                $new_component->{count} = $comp_count;
                $comp_count = 0;
            }
            $cur_component = $comp;

            $new_component = {
                'name' => $comp,
                'bug_list' => []
            };
            push @{$comp_list}, $new_component;
            $cur_bug = 0;
            $bug_list = $new_component->{bug_list};
        }

        # Check if we've moved on to a new bug
        if ($cur_bug ne $bug_id) {
            $cur_bug = $bug_id;

            $sth_Buginfo->execute($bug_id);
            my ($bug_desc, $priority, $severity) = $sth_Buginfo->fetchrow_array;

            my $new_bug = {
                'id' => $bug_id,
                'summary' => $bug_desc,
                'priority' => $priority,
                'severity' => $severity,
                'patch_list' => []
            };
            push @{$bug_list}, $new_bug;
            $patch_list = $new_bug->{patch_list};
        }

        my $new_patch = {
            'id' => $attach_id,
            'age' => $age,
            'description' => $desc
        };
        push @{$patch_list}, $new_patch;

        $total_count++;
        $prod_count++;
        $comp_count++;

        # printf "%6d %6d %s %s %s\n", $attach_id, $bug_id, $prod, $comp, $desc;
    }

    # Update the counts for the final product and component, as well as the total
    $stats->{count} = $total_count;
    $new_product->{count} = $prod_count;
    $new_component->{count} = $comp_count;

    return $stats;
}

