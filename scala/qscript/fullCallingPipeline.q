import org.broadinstitute.sting.queue.QScript._
// Other imports can be added here

val unparsedArgs  = setArgs(args)

// very slow-to-run fast-to-write parse args function. Only worth changing if using lots of flags with lots of lookups.

def parseArgs(flag: String): String = {
 val retNext: Boolean = false
 for ( f <- unparsedArgs ) {
  if ( retNext ) {
    return f
  } else {
    if ( f.equals(flag) ) {
      retNext = true
    }
  }
 }
  return "None"
}

/////////////////////////////////////////////////
// step one: we need to create a set of realigner targets, one for each bam file
/////////////////////////////////////////////////

class RealignerTargetCreator extends GatkFunction {
 @Gather(classOf[SimpleTextGatherFunction])
 @Output(doc="Realigner targets")
 var realignerIntervals: File = _

 def commandLine = gatkCommandLine("RealignerTargetCreator") + "-o %s".format(realignerIntervals)
}

/////////////////////////////////////////////////
// step two: we need to clean each bam file - gather will fix mates
/////////////////////////////////////////////////

class IndelRealigner extends GatkFunction {
 @Input(doc="Intervals to clean")
 var intervalsToClean: File = _
 @Gather(classOf[FixMatesGatherFunction])
 @Output(doc="Cleaned bam file")
 var cleanedBam: File = _

 def commandLine = gatkCommandLine("IndelRealigner") + "--output %s -targetIntervals %s".format(cleanedBam,intervalsToClean)
}

/////////////////////////////////////////////////
// step three: we need to call (multisample) over all bam files
/////////////////////////////////////////////////

class UnifiedGenotyper extends GatkFunction {
 @Gather(classOf[SimpleTextGatherFunction])
 @Output(doc="raw vcf")
 var rawVCF: File = _
 // todo -- add input for comps, triggers, etc

 def commandLine = gatkCommandLine("UnifiedGenotyper") + "-G Standard -A MyHaplotypeScore -varout %s".format(rawVCF)
}

/////////////////////////////////////////////////
// step four: we need to call indels (multisample) over all bam files
/////////////////////////////////////////////////

class UnifiedGenotyperIndels extends GatkFunction {
 @Output(doc="indel vcf")
 var indelVCF: File = _
 @Gather(classOf[SimpleTextGatherFunction])
 // todo -- add inputs for the indel genotyper

 def commandLine = gatkCommandLine("UnifiedGenotyper") + "-varout %s -gm INDELS"
}

/////////////////////////////////////////////////
// step five: we need to filter variants on cluster and with indel mask
/////////////////////////////////////////////////
class VariantFiltration extends GatkFunction {
 @Input(doc="A VCF file to filter")
 var unfilteredVCF: File = _
 @Input(doc="An interval mask to use to filter indels")
 var indelMask: File = _
 @Input(doc="Filter names",required=false)
 var filterNames: List[String] = Nil
 @Input(doc="Filter expressions",required=false)
 var filterExpressions: List[String] = Nil
 @Output(doc="The input VCF file, but filtered")
 var filteredVCF: File = _
 // to do -- snp cluster args?

 def commandLine = gatkCommandLine("VariantFiltration") + "-B variant,VCF,%s -B mask,VCF,%s --maskName NearIndel --clusterWindowSize 20 --clusterSize 7 -o %s".format(unfilteredVCF,indelMask,filteredVCF) +
                    "%s%s".format(repeat(" -filterName ",filterNames), repeat(" -filterExpression ",filterExpressions))
}

/////////////////////////////////////////////////
// step six: we need to generate gaussian clusters with the optimizer
/////////////////////////////////////////////////
class GenerateVariantClusters extends GatkFunction {
 @Input(doc="A VCF that has been filtered for clusters and indels")
 var initialFilteredVCF: File = _
 @Output(doc="Variant cluster file generated from input VCF")
 var clusterFile: File = _
 // todo -- args for annotations?
 // todo -- args for resources (properties file)

 def commandLine = gatkCommandLine("GenerateVariantClusters") + "-an QD -an SB -an MyHaplotypeScore -an HRun "
  +"-resources /humgen/gsa-scr1/chartl/sting/R -B input,VCF,%s -clusterFile %s".format(initialFilteredVCF,clusterFile)
}

/////////////////////////////////////////////////
// step seven: we need to apply gaussian clusters to our variants
/////////////////////////////////////////////////
class ApplyGaussianClusters extends GatkFunction {
 @Input(doc="A VCF file to which to apply clusters")
 var inputVCF: File = _
 @Input(doc="A variant cluster file")
 var clusterFile: File = _
 @Output(doc="A quality-score recalibrated VCF file")
 var recalibratedVCF: File = _
 // todo -- inputs for Ti/Tv expectation and other things

 def commandLine = gatkCommandLine("VariantRecalibrator") + "--target_titv 2.1 -resources /humgen/gsa-scr1/chartl/sting/R "
  +"-B input,VCF,%s -clusterFile %s -output %s".format(inputVCF,clusterFile,recalibratedVCF)
}

/////////////////////////////////////////////////
// step eight: we need to make tranches out of the recalibrated qualities
/////////////////////////////////////////////////
class ApplyVariantCuts extends GatkFunction {
 @Input(doc="A VCF file that has been recalibrated")
 var recalibratedVCF: File = _
 @Output(doc="A VCF file that has had tranches marked")
 var tranchedVCF: File = _
 @Output(doc="A tranch dat file")
 var tranchFile: File = _
 // todo -- fdr inputs, etc

 def commandLine = gatkCommandLine("ApplyVariantCuts") + "-B input,VCF,%s -outputVCF %s --tranchesFile %s --fdr_filter_level 10.0"
}

/////////////////////////////////////////////////
// step nine: we need to annotate variants using the annotator [or maf, for now]
/////////////////////////////////////////////////
class GenomicAnnotator extends GatkFunction {
 @Input(doc="A VCF file to be annotated")
 var inputVCF: File = _
 @Input(doc="Refseq input table to use with the annotator")
 var refseqTable: File = _
 @Input(doc="Dbsnp input table to use with the annotator")
 var dbsnpTable: File = _
 @Gather(classOf[SimpleTextGatherFunction])
 @Output(doc="A genomically annotated VCF file")
 var annotatedVCF: File = _

 def commandLine = gatkCommandLine("GenomicAnnotator") + " -B variant,VCF,%s -B refseq,AnnotatorInputTable,%s -B dbsnp,AnnotatorInputTable,%s -vcf %s -s dbsnp.name,dbsnp.refUCSC,dbsnp.strand,dbsnp.observed,dbsnp.avHet".format(inputVCF,refseqTable,dbsnpTable,annotatedVCF)
}

/////////////////////////////////////////////////
// step ten: we need to evaluate variants with variant eval
/////////////////////////////////////////////////
class VariantEval extends GatkFunction {
 @Input(doc="An optimized vcf file to evaluate")
 var optimizedVCF: File = _
 @Input(doc="A hand-fitlered vcf file to evaluate")
 var handFilteredVCF: File = _
 @Output(doc="An evaluation file")
 var evalOutput: File = _
 // todo -- input for additional comp tracks

 def commandLine = gatkCommandLine("VariantEval") + "-B evalOptimized,VCF,%s -B evalHandFiltered,VCF,%s -E CountFunctionalClasses -E CompOverlap -E CountVariants -E TiTvVariantEvaluator -o %s".format(optimizedVCF,handFilteredVCF,evalOutput)
}

// ------------ SETUP THE PIPELINE ----------- //

// todo -- the unclean and clean pipelines are the same, so the code can be condensed significantly

// there are commands that use all the bam files

val cleanSNPCalls = new UnifiedGenotyper
val uncleanSNPCalls = new UnifiedGenotyper
val cleanIndelCalls = new UnifiedGenotyper
val uncleanIndelCalls = new UnifiedGenotyper

for ( bam <- inputs("bam") ) {

 // put unclean bams in unclean genotypers

  uncleanSNPCalls.bamFiles += bam
  uncleanIndelCalls.bamFiles += bam

 // in advance, create the extension files

 val indel_targets = swapExt(bam,"bam","realigner_targets.interval_list")
 val cleaned_bam = swapExt(bam,"bam","cleaned.bam")

 // create the cleaning commands

 val targetCreator = new RealignerTargetCreator
 targetCreator.bamFiles += bam
 targetCreator.realignerTargets = indel_targets

 val realigner = new IndelRealigner
 realigner.bamFiles = targetCreator.bamFiles
 realigner.cleanedBam = cleaned_bam

 // put clean bams in clean genotypers

  cleanSNPCalls.bamFiles += realigner.cleanedBam
  cleanIndelCalls.bamFiles += realigner.cleanedBam

  add(targetCreator,realigner)
}

val projectBase: String = parseArgs("-project")
val cleanedBase: String = projectBase + ".cleaned"
val uncleanedBase: String = projectBase + ".uncleaned"

def endToEnd(base: String, snps: UnifiedGenotyper, indels: UnifiedGenotyperIndels) = {

// step through the un-indel-cleaned graph:
// 1a. call snps and indels
snps.rawVCF = base+".vcf"
indels.rawVCF = base+".indels.vcf"
// 1b. genomically annotate SNPs
val annotated = new GenomicAnnotator
annotated.inputVCF = snps.rawVCF
annotated.annotatedVCF = swapExt(snps.rawVCF,".vcf",".annotated.vcf")
// 2.a filter on cluster and near indels
val masker = new VariantFiltration
masker.unfilteredVCF = annotated.annotatedVCF
masker.indelMask = indels.rawVCF
masker.filteredVCF = swapExt(uncleanAnnotatedSNPCalls.annotatedVCF,".vcf",".indel.masked.vcf")
// 2.b hand filter with standard filter
val handFilter = new VariantFiltration
handFilter.unfilteredVCF = annotated.annotatedVCF
handFilter.indelMask = indels.rawVCF
handFilter.filterNames = List("StrandBias","AlleleBalance","QualByDepth","HomopolymerRun")
handFilter.filterExpressions = List("SB>=0.10","AB>=0.75","QD<5","HRun>=4")
handFilter.filteredVCF = swapExt(annotated.annotatedVCF,".vcf",".handfiltered.vcf")
// 3.i generate gaussian clusters on the masked vcf
val clusters = new GenerateVariantClusters
clusters.initialFilteredVCF = masker.filteredVCF
clusters.clusterFile = swapExt(snps.rawVCF,".vcf",".cluster")
// 3.ii apply gaussian clusters to the masked vcf
val recalibrate = new ApplyGaussianClusters
recalibrate.clusterFile = clusters.clusterFile
recalibrate.inputVCF = masker.filteredVCF
recalibrate.recalibratedVCF = swapExt(masker.filteredVCF,".vcf",".optimized.vcf")
// 3.iii apply variant cuts to the clusters
val cut = new ApplyVariantCuts
cut.recalibratedVCF = recalibrate.recalibratedVCF
cut.tranchedVCF = swapExt(recalibrate.recalibratedVCF,".vcf",".tranched.vcf")
cut.tranchFile = swapExt(recalibrate.recalibratedVCF,".vcf",".tranch")
// 4. Variant eval the cut and the hand-filtered vcf files
val eval = new VariantEval
eval.optimizedVCF = cut.tranchedVCF
eval.handFilteredVCF = handFilter.filteredVCF
eval.evalOutput = base+".eval"

add(snps,indels,annotated,masker,handFilter,clusters,recalibrate,cut,eval)
}

endToEnd(uncleanedBase,uncleanSNPCalls,uncleanIndelCalls)
endToEnd(cleanedBase,cleanSNPCalls,cleanIndelCalls)