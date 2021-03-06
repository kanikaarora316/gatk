/*
* Copyright (c) 2012 The Broad Institute
* 
* Permission is hereby granted, free of charge, to any person
* obtaining a copy of this software and associated documentation
* files (the "Software"), to deal in the Software without
* restriction, including without limitation the rights to use,
* copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the
* Software is furnished to do so, subject to the following
* conditions:
* 
* The above copyright notice and this permission notice shall be
* included in all copies or substantial portions of the Software.
* 
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
* OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
* NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
* HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
* WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR
* THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

package org.broadinstitute.sting.gatk.walkers.varianteval.evaluators;

import org.apache.log4j.Logger;
import org.broadinstitute.sting.gatk.contexts.AlignmentContext;
import org.broadinstitute.sting.gatk.contexts.ReferenceContext;
import org.broadinstitute.sting.gatk.refdata.RefMetaDataTracker;
import org.broadinstitute.sting.gatk.walkers.varianteval.util.Analysis;
import org.broadinstitute.sting.gatk.walkers.varianteval.util.DataPoint;
import org.broadinstitute.sting.utils.Utils;
import org.broadinstitute.sting.utils.variant.GATKVariantContextUtils;
import org.broadinstitute.variant.variantcontext.Allele;
import org.broadinstitute.variant.variantcontext.VariantContext;

@Analysis(description = "Evaluation summary for multi-allelic variants")
public class MultiallelicSummary extends VariantEvaluator implements StandardEval {
    final protected static Logger logger = Logger.getLogger(MultiallelicSummary.class);

    public enum Type {
        SNP, INDEL
    }

    // basic counts on various rates found
    @DataPoint(description = "Number of processed loci", format = "%d")
    public long nProcessedLoci = 0;

    @DataPoint(description = "Number of SNPs", format = "%d")
    public int nSNPs = 0;
    @DataPoint(description = "Number of multi-allelic SNPs", format = "%d")
    public int nMultiSNPs = 0;
    @DataPoint(description = "% processed sites that are multi-allelic SNPs", format = "%.5f")
    public double processedMultiSnpRatio = 0;
    @DataPoint(description = "% SNP sites that are multi-allelic", format = "%.3f")
    public double variantMultiSnpRatio = 0;

    @DataPoint(description = "Number of Indels", format = "%d")
    public int nIndels = 0;
    @DataPoint(description = "Number of multi-allelic Indels", format = "%d")
    public int nMultiIndels = 0;
    @DataPoint(description = "% processed sites that are multi-allelic Indels", format = "%.5f")
    public double processedMultiIndelRatio = 0;
    @DataPoint(description = "% Indel sites that are multi-allelic", format = "%.3f")
    public double variantMultiIndelRatio = 0;

    @DataPoint(description = "Number of Transitions", format = "%d")
    public int nTi = 0;
    @DataPoint(description = "Number of Transversions", format = "%d")
    public int nTv = 0;
    @DataPoint(description = "Overall TiTv ratio", format = "%.2f")
    public double TiTvRatio = 0;

    @DataPoint(description = "Multi-allelic SNPs partially known", format = "%d")
    public int knownSNPsPartial = 0;
    @DataPoint(description = "Multi-allelic SNPs completely known", format = "%d")
    public int knownSNPsComplete = 0;
    @DataPoint(description = "Multi-allelic SNP Novelty Rate")
    public String SNPNoveltyRate = "NA";

    //TODO -- implement me
    //@DataPoint(description = "Multi-allelic Indels partially known", format = "%d")
    public int knownIndelsPartial = 0;
    //@DataPoint(description = "Multi-allelic Indels completely known", format = "%d")
    public int knownIndelsComplete = 0;
    //@DataPoint(description = "Multi-allelic Indel Novelty Rate")
    public String indelNoveltyRate = "NA";


    @Override public int getComparisonOrder() { return 2; }

    public void update2(VariantContext eval, VariantContext comp, RefMetaDataTracker tracker, ReferenceContext ref, AlignmentContext context) {
        if ( eval == null || (getWalker().ignoreAC0Sites() && eval.isMonomorphicInSamples()) )
            return;

        // update counts
        switch ( eval.getType() ) {
            case SNP:
                nSNPs++;
                if ( !eval.isBiallelic() ) {
                    nMultiSNPs++;
                    calculatePairwiseTiTv(eval);
                    calculateSNPPairwiseNovelty(eval, comp);
                }
                break;
            case INDEL:
                nIndels++;
                if ( !eval.isBiallelic() ) {
                    nMultiIndels++;
                    calculateIndelPairwiseNovelty(eval, comp);
                }
                break;
            default:
                //throw new UserException.BadInput("Unexpected variant context type: " + eval);
                break;
        }

        return;
    }

    private void calculatePairwiseTiTv(VariantContext vc) {
        for ( Allele alt : vc.getAlternateAlleles() ) {
            if ( GATKVariantContextUtils.isTransition(vc.getReference(), alt) )
                nTi++;
            else
                nTv++;
        }
    }

    private void calculateSNPPairwiseNovelty(VariantContext eval, VariantContext comp) {
        if ( comp == null )
            return;

        int knownAlleles = 0;
        for ( Allele alt : eval.getAlternateAlleles() ) {
            if ( comp.getAlternateAlleles().contains(alt) )
                knownAlleles++;
        }

        if ( knownAlleles == eval.getAlternateAlleles().size() )
            knownSNPsComplete++;
        else if ( knownAlleles > 0 )
            knownSNPsPartial++;
    }

    private void calculateIndelPairwiseNovelty(VariantContext eval, VariantContext comp) {
        // TODO -- implement me
    }

    public void finalizeEvaluation() {
        nProcessedLoci = getWalker().getnProcessedLoci();
        processedMultiSnpRatio = (double)nMultiSNPs / (double)nProcessedLoci;
        variantMultiSnpRatio = (double)nMultiSNPs / (double)nSNPs;
        processedMultiIndelRatio = (double)nMultiIndels / (double)nProcessedLoci;
        variantMultiIndelRatio = (double)nMultiIndels / (double)nIndels;

        TiTvRatio = (double)nTi / (double)nTv;

        SNPNoveltyRate = Utils.formattedNoveltyRate(knownSNPsPartial + knownSNPsComplete, nMultiSNPs);
        indelNoveltyRate = Utils.formattedNoveltyRate(knownIndelsPartial + knownIndelsComplete, nMultiSNPs);
    }
}
