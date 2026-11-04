use strict;
use warnings;

# Unity's BinaryFormatter writes each boxed language enum as a
# ClassWithMembersAndTypes record containing one Int32 member, value__.
# Validate both records before replacing either value.
my ($mode, $path) = @ARGV;
open my $input, '<:raw', $path or die "$path: $!\n";
my $data = do { local $/; <$input> } // '';
close $input or die "$path: $!\n";

my $header = pack 'CVVVV', 0, 1, 0xffffffff, 1, 0;
exit 2 unless index($data, $header) == 0
    && index($data, 'UI_MainMenu_Settings_Controller+SettingsData') >= 0
    && substr($data, -1) eq "\x0b";

my @offsets;
for my $type ('LanguageManager+ID', 'SpeechCommand.Language') {
    my $name = pack('C', length($type)) . $type;
    my $members = pack('VC', 1, 7) . 'value__' . "\x00\x08";
    my @matches;
    while ($data =~ /\x05.{4}\Q$name$members\E.{4}(.{4})/sg) {
        push @matches, $-[1];
    }
    exit 2 unless @matches == 1;
    push @offsets, $matches[0];
}

if ($mode eq 'report') {
    binmode STDOUT, ':raw';
    # Menu and speech have different enum orders after English and Russian.
    my @languages = (
        [qw(English Russian Ukrainian Polish Chinese Italian German Spanish Turkish Hungarian French)],
        [qw(English Russian Ukrainian Italian German Spanish Chinese Turkish French)],
    );
    my @labels = ('Интерфейс', 'Распознавание речи и реплики ритуалов');
    for my $i (0 .. $#offsets) {
        my $value = unpack 'V', substr($data, $offsets[$i], 4);
        my $language = $languages[$i][$value] // "неизвестное значение ($value)";
        print "$labels[$i]: $language\n";
    }
    my $ready = !grep { unpack('V', substr($data, $_, 4)) != 1 } @offsets;
    print $ready ? "Статус: оба языка уже русские\n" : "Статус: можно применить исправление\n";
    exit 0;
}

my $russian = pack 'V', 1;
my @changes = grep { substr($data, $_, 4) ne $russian } @offsets;
exit 0 unless @changes;
exit 1 if $mode eq 'check';
die "Unknown mode: $mode\n" unless $mode eq 'patch';

substr($data, $_, 4, $russian) for @changes;
open my $output, '>:raw', $path or die "$path: $!\n";
print {$output} $data or die "$path: $!\n";
close $output or die "$path: $!\n";
