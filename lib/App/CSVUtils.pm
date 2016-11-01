package App::CSVUtils;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

our %SPEC;

sub _compile {
    my $str = shift;
    defined($str) && length($str) or die "Please specify code (-e)\n";
    $str = "sub { $str }";
    my $code = eval $str;
    die "Can't compile code (-e) '$str': $@\n" if $@;
    $code;
}

sub _get_field_idx {
    my ($field, $field_idxs) = @_;
    defined($field) && length($field) or die "Please specify field (-F)\n";
    my $idx = $field_idxs->{$field};
    die "Unknown field '$field'\n" unless defined $idx;
    $idx;
}

sub _get_csv_row {
    my ($csv, $row, $i) = @_;
    my $status = $csv->combine(@$row)
        or die "Error in line $i: ".$csv->error_input."\n";
    $csv->string . "\n";
}

my %arg_filename_1 = (
    filename => {
        summary => 'Input CSV file',
        schema => 'filename*',
        req => 1,
        pos => 1,
        cmdline_aliases => {f=>{}},
    },
);

my %arg_filename_0 = (
    filename => {
        summary => 'Input CSV file',
        schema => 'filename*',
        req => 1,
        pos => 0,
        cmdline_aliases => {f=>{}},
    },
);

my %arg_field_1 = (
    field => {
        summary => 'Field name',
        schema => 'str*',
        cmdline_aliases => { F=>{} },
        req => 1,
        pos => 1,
    },
);

my %arg_eval_2 = (
    eval => {
        summary => 'Perl code to do munging',
        schema => 'str*',
        cmdline_aliases => { e=>{} },
        req => 1,
        pos => 2,
    },
);

$SPEC{csvutil} = {
    v => 1.1,
    summary => 'Perform action on a CSV file',
    args => {
        action => {
            schema => ['str*', in=>[
                'list-field-names',
                'munge-field',
                'delete-field',
                'add-field',
            ]],
            req => 1,
            pos => 0,
            cmdline_aliases => {a=>{}},
        },
        %arg_filename_1,
        eval => {
            summary => 'Perl code to do munging',
            schema => 'str*',
            cmdline_aliases => { e=>{} },
        },
        field => {
            summary => 'Field name',
            schema => 'str*',
            cmdline_aliases => { F=>{} },
        },
    },
    args_rels => {
    },
};
sub csvutil {
    require Text::CSV_XS;

    my %args = @_;
    my $action = $args{action};

    my $csv = Text::CSV_XS->new({binary => 1});
    open my($fh), "<:encoding(utf8)", $args{filename} or
        return [500, "Can't open input filename '$args{filename}': $!"];

    my $res = "";
    my $i = 0;
    my $fields;
    my %field_idxs;

    my $code;
    my $field_idx;

    while (my $row = $csv->getline($fh)) {
        $i++;
        if ($i == 1) {
            $fields = $row;
            for my $j (0..$#{$row}) {
                unless (length $row->[$j]) {
                    #return [412, "Empty field name in field #$j"];
                    next;
                }
                if (defined $field_idxs{$row->[$j]}) {
                    return [412, "Duplicate field name '$row->[$j]'"];
                }
                $field_idxs{$row->[$j]} = $j;
            }
        }
        if ($action eq 'list-field-names') {
            return [200, "OK",
                    [map { {name=>$_, index=>$field_idxs{$_}+1} }
                         sort keys %field_idxs],
                    {'table.fields'=>['name','index']}];
        } elsif ($action eq 'munge-field') {
            unless ($code) {
                $code = _compile($args{eval});
                $field_idx = _get_field_idx($args{field}, \%field_idxs);
            }
            if (defined $row->[$field_idx]) {
                local $_ = $row->[$field_idx];
                local $main::row = $row;
                local $main::rownum = $i;
                eval { $code->($_) };
                die "Error while munging row ".
                    "#$i field '$args{field}' value '$_': $@\n" if $@;
                $row->[$field_idx] = $_;
            }
            $res .= _get_csv_row($csv, $row, $i);
        } elsif ($action eq 'add-field') {
            unless ($code) {
                $code = _compile($args{eval});
                if (!defined($args{field}) || !length($args{field})) {
                    return [400, "Please specify field (-F)"];
                }
                if (defined $field_idxs{$args{field}}) {
                    return [412, "Field '$args{field}' already exists"];
                }
                $field_idx = @$row;
                push @$row, $args{field};
            }
            if (!defined($row->[$field_idx])) {
                local $_;
                local $main::row = $row;
                local $main::rownum = $i;
                eval { $_ = $code->() };
                die "Error while adding field '$args{field}' for row #$i: $@\n"
                    if $@;
                $row->[$field_idx] = $_;
            }
            $res .= _get_csv_row($csv, $row, $i);
        } elsif ($action eq 'delete-field') {
            unless (defined $field_idx) {
                $field_idx = _get_field_idx($args{field}, \%field_idxs);
                if (@$row <= 1) {
                    return [412, "Can't delete field because CSV will have zero fields"];
                }
            }
            splice @$row, $field_idx, 1;
            $res .= _get_csv_row($csv, $row, $i);
        } else {
            return [400, "Unknown action '$action'"];
        }
    }

    [200, "OK", $res, {"cmdline.skip_format"=>1}];
}

$SPEC{csv_add_field} = {
    v => 1.1,
    summary => 'Add a field to CSV file',
    description => <<'_',

This command:

    % csv-add-field FILE.CSV FIELDNAME 'perl code'

is equivalent to:

    % csvutil add-field FILE.CSV -F FIELDNAME -e 'perl code'

Your Perl code should return the value for the field. `$main::row` is available
and contains the current row, while `$main::rownum` contains the row number (1
means the header row, 2 means the first data row). Field will be added as the
last field.

_
    args => {
        %arg_filename_0,
        %arg_field_1,
        %arg_eval_2,
    },
};
sub csv_add_field {
    my %args = @_;
    csvutil(%args, action=>'add-field');
}

$SPEC{csv_list_field_names} = {
    v => 1.1,
    summary => 'List field names of CSV file',
    args => {
        %arg_filename_0,
    },
};
sub csv_list_field_names {
    my %args = @_;
    csvutil(%args, action=>'list-field-names');
}

$SPEC{csv_delete_field} = {
    v => 1.1,
    summary => 'Delete a field from CSV file',
    description => <<'_',

This command:

    % csv-delete-field FILE.CSV FIELDNAME

is equivalent to:

    % csvutil delete-field FILE.CSV -F FIELDNAME

Field must exist and there must be at least one remaining field after deletion.

_
    args => {
        %arg_filename_0,
        %arg_field_1,
    },
};
sub csv_delete_field {
    my %args = @_;
    csvutil(%args, action=>'delete-field');
}

$SPEC{csv_munge_field} = {
    v => 1.1,
    summary => 'Munge a field in every row of CSV file',
    description => <<'_',

This command:

    % csv-munge-field FILE.CSV FIELDNAME 'perl code'

is equivalent to:

    % csvutil munge-field FILE.CSV -F FIELDNAME -e 'perl code'

Perl code will be called for each row and `$_` will contain the value of the
field `FIELDNAME`, which the Perl code is expected to modify. `$main::row` will
contain the current row array and `$main::rownum` contains the row number (1
means the header row, 2 means the first data row).

_
    args => {
        %arg_filename_0,
        %arg_field_1,
        %arg_eval_2,
    },
};
sub csv_munge_field {
    my %args = @_;
    csvutil(%args, action=>'munge-field');
}

1;
# ABSTRACT: CLI utilities related to CSV

=head1 DESCRIPTION

This distribution contains the following CLI utilities:

# INSERT_EXECS_LIST


=head1 SEE ALSO

=cut