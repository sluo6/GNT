#!/usr/bin/env perl

BEGIN {
    die "The efiest environment must be loaded before running this script" if not exists $ENV{EFIEST} or not exists $ENV{EFIDBPATH};
}

use Getopt::Long;
#use List::MoreUtils qw{apply uniq any} ;
#use XML::LibXML;
#use DBD::SQLite;
#use DBD::mysql;
#use IO;
#use XML::Writer;
use File::Slurp;
#use XML::LibXML::Reader;
#use List::Util qw(sum);
#use Array::Utils qw(:all);
use Capture::Tiny qw(:all);

use lib $ENV{EFIEST} . "/lib";
use Biocluster::Database;

#$configfile=read_file($ENV{'EFICFG'}) or die "could not open $ENV{'EFICFG'}\n";
#eval $configfile;

my ($result, $nodeDir, $fastaDir, $configFile);
$result = GetOptions(
    "node-dir=s"        => \$nodeDir,
    "out-dir=s"         => \$fastaDir,
    "config=s"          => \$configFile,
);

my $usage=<<USAGE
usage: getfasta.pl -data-dir <path_to_data_dir> -config <config_file>
    -node-dir       path to directory containing lists of IDs (one file/list per cluster number)
    -out-dir        path to directory to output fasta files to
    -config         path to configuration file
USAGE
;


if (not -d $nodeDir) {
    die "The input data directory must be specified and exist.\n$usage";
}


my $db = new Biocluster::Database(config_file => $configFile);
my $dbh = $db->getHandle();

my $blastDbPath = $ENV{EFIDBPATH};


foreach my $file (glob("$nodeDir/cluster_nodes_*.txt")) {
    (my $clusterNum = $file) =~ s%^.*/cluster_nodes_(\d+)\.txt$%$1%;
    
    open FASTA, ">$fastaDir/cluster_$clusterNum.fasta";
    open NODES, $file;

    my $hasLines = 1;
    my $nodeCount = 0;

    my @ids = map { $_ =~ s/[\r\n]//g; $_ } read_file($file);

    print "Retrieving sequences for cluster $clusterNum...\n";

    while (scalar @ids) {
        my $batchLine = join(",", splice(@ids, 0, 1000));
        my ($fastacmdOutput, $fastaErr) = capture {
            system("fastacmd", "-d", "$blastDbPath/combined.fasta", "-s", $batchLine);
        };
        my @sequences = split /\n>/, $fastacmdOutput;
        $sequences[0] = substr($sequences[0], 1) if $#sequences >= 0 and substr($sequences[0], 0, 1) eq ">";
        foreach my $seq (@sequences) {
            if ($seq =~ s/^\w\w\|(\w{6,10})\|.*//) {
                my $accession = $1;
                my $sql = "select Organism,PFAM from annotations where accession = '$accession'";
                my $sth = $dbh->prepare($sql);
                $sth->execute();
                
                my $organism = "Unknown";
                my $pfam = "Unknown";

                my $row = $sth->fetchrow_hashref();
                if ($row) {
                    $organism = $row->{Organism};
                    $pfam = $row->{PFAM};
                }

                print FASTA ">$clusterNum:$accession:$organism:$pfam$seq\n";
            }
        }
    }

    print "Done retrieving sequences!\n";

    close NODES;
    close FASTA;
}


$dbh->disconnect();

