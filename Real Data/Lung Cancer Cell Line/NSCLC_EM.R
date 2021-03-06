setwd("C:/Users/David/Desktop/Research/EM/Real Data/Lung Cancer Cell Line")
#setwd("/netscr/deelim")
library("parallel")

no_cores<-detectCores()-1
cl<-makeCluster(no_cores,outfile="NSCLC_EM_cluster_output.txt")

library("stats")
library("data.table")
library("DESeq2")

anno<-read.table("NSCLC_anno.txt",sep="\t",header=TRUE)
dat<-read.table("NSCLC_rsem.genes.exp.count.unnormalized.txt",sep="\t",header=TRUE)
row_names<-toupper(dat[,1])
dat<-round(dat[,-1],digits=0)

# DESeq2 to find size factors
cts<-as.matrix(dat)
rownames(cts)<-row_names

colnames(cts)<-toupper(colnames(cts))
coldata<-anno[,-1]
rownames(coldata)<-toupper(anno[,1])
coldata<-coldata[,c("Adeno.Squamous","Tumor.location")]
#all(rownames(coldata) %in% colnames(cts))         # check that headers are correct
#all(rownames(coldata) == colnames(cts))
dds<-DESeqDataSetFromMatrix(countData = cts,
                            colData = coldata,
                            design = ~ Adeno.Squamous)
DESeq_dds<-DESeq(dds)
size_factors<-sizeFactors(DESeq_dds)

norm_y<-counts(DESeq_dds,normalized=TRUE)

res<-results(DESeq_dds,alpha=0.05)
signif_res<-res[is.na(res$padj)==FALSE,]
signif_res<-signif_res[order(signif_res$padj),]
signif_res<-signif_res[1:100,]



# initial clean-up of data and pre-filtering to include only genes with >=100 count
dat<-read.table("NSCLC_rsem.genes.exp.count.unnormalized.txt",sep="\t",header=TRUE)
rownames(dat)<-toupper(dat[,1])
dat<-dat[,-1]
signif_dat<-dat[toupper(rownames(signif_res)),]      # Subsetting just the significant genes from DESeq2
y<-round(signif_dat,digits=0)
y<-y[(rowSums(y)>=100),]

#########################################################################
# # SAVING TOP GENES (y, norm_y, size_factors, and phi) FOR SIMULATIONS #
# norm_y<-y
# n=ncol(y)
# g=nrow(y)
# for(i in 1:ncol(y)){
#   norm_y[,i] = y[,i]/size_factors[i]
# }
# setwd("C:/Users/David/Desktop/Research/EM")
# write.table(norm_y,"init_norm_y.txt")
# write.table(y,"init_y.txt")
# write.table(size_factors,"init_size_factors.txt")
# true_clusters = as.numeric(anno$Adeno.Squamous)
# k=length(unique(true_clusters))
# 
# wts = matrix(0,nrow=k,ncol=n)
# for(c in 1:k){
#   wts[c,]=(true_clusters==c)^2
# }
# 
# phi = matrix(0,nrow=g,ncol=k)
# for(j in 1:g){
#   for(c in 1:k){
#     if(all((as.numeric(y[j,true_clusters==c])-as.numeric(y[j,true_clusters==c])[1]==0))){
#       phi[j,c]=0
#     }else{ phi[j,c]=1/glm.nb(as.numeric(y[j,]) ~ 1 + offset(log(size_factors)),weights = wts[c,])$theta }
#   }
# }
# 
# write.table(phi,"init_phi.txt")
############################################################################





# filtering genes to have top 500 MAD (median absolute deviation): optional

# med_abs_dev<-rep(0,times=nrow(y))
# for(j in 1:nrow(y)){
#   med_abs_dev[j]<-mad(as.numeric(y[j,]),constant=1)
# }
# y<-cbind(rownames(y),y,med_abs_dev)
# subs_y<-as.data.table(y)[order(-med_abs_dev),head(.SD,100)]
# genes_y<-subs_y[,1]
# subs_y<-subs_y[,-1]
# subs_y<-as.data.frame(subs_y[,-24])
# 



# k=2        # known

# grid search for tuning params lambda1 and lambda2 and K
# Wei Pan
source("C:/Users/David/Desktop/Research/EM/NB Pan EM.R")
#source("Pan EM.R")

K_search=c(2:7)
list_BIC=matrix(0,nrow=length(K_search),ncol=2)
list_BIC[,1]=K_search

for(aa in 1:nrow(list_BIC)){
  list_BIC[aa,2]<-EM(y=y,k=list_BIC[aa,1],lambda1=0,lambda2=0,tau=0,size_factors=size_factors,norm_y=norm_y)$BIC   # no penalty Pan
  #list_BIC[aa,2]<-EM(y=y,k=list_BIC[aa,1],size_factors=size_factors)$BIC       # unpenalized (not Pan)
  print(list_BIC[aa,])
}

max_k=list_BIC[which(list_BIC[,2]==min(list_BIC[,2])),1]
choose_k[ii]<-max_k

lambda1_search=1
lambda2_search=c(0.01,0.05,0.1,0.2,0.5,1)
tau_search=seq(from=0.1,to=0.9,by=0.2)
K_search=max_k

list_BIC=matrix(0,nrow=length(lambda1_search)*length(lambda2_search)*length(K_search)*length(tau_search),ncol=5) #matrix of BIC's: lambda1 and lambda2 and K, 49*5 combinations

list_BIC[,1]=rep(lambda1_search,each=length(lambda2_search)*length(K_search)*length(tau_search))
list_BIC[,2]=rep(rep(lambda2_search,each=length(K_search)*length(tau_search)),times=length(lambda1_search))
list_BIC[,3]=rep(rep(K_search,each=length(tau_search)),times=length(lambda1_search)*length(lambda2_search))
list_BIC[,4]=rep(tau_search,times=length(lambda1_search)*length(lambda2_search)*length(K_search))

extract_BIC<-function(row){
  X<-EM(y=y,k=list_BIC[row,3],lambda1=list_BIC[row,1],lambda2=list_BIC[row,2],tau=list_BIC[row,4],size_factors=size_factors,norm_y=norm_y)
  print(paste("lambda1 =",list_BIC[row,1],"and lambda2 =",list_BIC[row,2],"and K =",list_BIC[row,3],"and tau =",list_BIC[row,4],"pi=",X$pi,"BIC=",X$BIC,"nondisc=",mean(X$nondiscriminatory)))
  return(X$BIC)
}
clusterExport(cl,c("subs_y","y","size_factors","norm_y","list_BIC","EM","logsumexpc","soft_thresholding"))
clusterExport(cl,"extract_BIC")
# actual grid search run
list_BIC[,5]<-parSapply(cl,1:nrow(list_BIC),extract_BIC) # Wei Pan

# storing optimal BIC index & optimal parameters
max_index<-which(list_BIC[,ncol(list_BIC)]==min(list_BIC[,ncol(list_BIC)]))
if(length(max_index)>1){
  warning("More than one max index")
  max_index<-max_index[1]
}

max_lambda1<-list_BIC[max_index,1]
max_lambda2<-list_BIC[max_index,2]
max_k<-list_BIC[max_index,3]
max_tau<-list_BIC[max_index,4]             # Wei Pan

print(paste("lambda1, lambda2, k, tau =", max_lambda1, max_lambda2, max_k, max_tau))    # Wei Pan

# actual run:
X<-EM(y=y,k=max_k,lambda1=max_lambda1,lambda2=max_lambda2,tau=max_tau,size_factors=size_factors,norm_y=norm_y) # Wei Pan


stopCluster(cl)

# summarize output #
sink("NSCLC_EM_Pan.txt",append=FALSE)
print("Results")
print(paste("pi =",X$pi))
print(paste("mean % of nondiscriminatory genes =",X$nondiscriminatory))
print(paste("final (lambda1,lambda2) =",max_lambda1,max_lambda2))   # Wei Pan
print(paste("final clusters:",X$final_clusters))
sink()

sink("NSCLC_EM_coefs_Pan.txt",append=FALSE)
print("coefs")
print(X$coefs)
sink()

