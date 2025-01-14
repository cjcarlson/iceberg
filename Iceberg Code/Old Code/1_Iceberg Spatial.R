# Rscript "Final Iceberg Code/1_Iceberg Spatial.R" ####

library(sf); library(fasterize); library(Matrix);library(ggplot2);
library(ggregplot); library(raster); library(tidyverse); library(igraph); 
library(maptools); library(SpRanger); library(parallel)

CORES = 60

t1 <- Sys.time()

PredReps <- c("Currents", paste0("Futures", 1:4))

if(CoryClimateReps[CR] == "gf"){
  
  PredReps <- c("Currents", paste0("Futures", 1:4))[c(1, 2, 4)]
  
}

RCPs <- c("2.6","4.5","7.0","8.5")

# Blanks
blank <- matrix(0,360*2,720*2) # proper resolution
blank <- raster(blank)
extent(blank) <- c(-180, 180, -90, 90)
projection(blank) <- CRS("+proj=longlat +datum=WGS84")

UniversalBlank <- raster("Iceberg Input Files/UniversalBlank.tif")
Land = which(raster::values(UniversalBlank)==0)
Sea = which(is.na(raster::values(UniversalBlank)))

# Grid areas
AreaRaster <- raster("Iceberg Input Files/LandArea.asc")
AreaValues <- raster::values(AreaRaster)

paste0("~/Albersnet/Iceberg Files/", 
       "Climate1/Iceberg Input Files/GretCDF/Currents") %>% 
  list.files() %>% 
  str_remove(".rds$") %>% sort ->
  Species

paste0("~/Albersnet/Iceberg Files/", 
       "Climate1/Iceberg Input Files/GretCDF/Currents") %>% 
  list.files(full.names = T) ->
  CurrentFiles

Species ->
  names(CurrentFiles)

paste0("Iceberg Input Files/GretCDF/Futures") %>% 
  list.files(full.names = T) ->
  FutureFiles

paste0("Iceberg Input Files/GretCDF/Futures") %>% 
  list.files() %>% 
  str_remove(".rds$") ->
  names(FutureFiles)

CurrentCDFList <- FutureCDFList <- list()

Species <- Species %>% sort %>% intersect(names(CurrentFiles)) #%>% intersect(names(FutureFiles))

CurrentFiles <- CurrentFiles[Species]
FutureFiles <- FutureFiles[Species]

PipelineReps <- LETTERS[1:4]

IcebergAdjList <- list()

if(file.exists(paste0("Iceberg Output Files/", "CurrentsRangeAdj", "A",".rds"))&
   file.exists(paste0("Iceberg Output Files/", "CurrentsRangeAdj", "B",".rds"))){
  
  print("Loading RangeAdj Files! Phew")
  
  IcebergAdjList$A <- IcebergAdjList$C <- IcebergAdjList$B <- IcebergAdjList$D <- list()
  
  IcebergAdjList$A$Currents <- 
    
    IcebergAdjList$C$Currents <- 
    
    readRDS(paste0("Iceberg Output Files/", "CurrentsRangeAdj", "A",".rds"))
  
  IcebergAdjList$B$Currents <- 
    
    IcebergAdjList$D$Currents <- 
    
    readRDS(paste0("Iceberg Output Files/", "CurrentsRangeAdj", "B",".rds"))
  
} else {
  
  CurrentCDFList <- mclapply(1:length(Species), function(a){
    
    Sp = Species[a]
    
    print(CurrentFiles[a])
    
    readRDS(CurrentFiles[[Sp]]) %>% as.matrix %>% as.data.frame() %>% dplyr::select(Climate, ClimateLandUse)
    
  }, mc.preschedule = F, mc.cores = CORES)
  
  object.size(CurrentCDFList)/(10^9)
  
  names(CurrentCDFList) <- Species
  
  for(Pipeline in LETTERS[1:4]){
    
    print(Pipeline)
    
    IcebergAdjList[[Pipeline]] <- list()
    
    if(Pipeline == "A"){
      
      CurrentVar <- "ClimateLandUse"
      FuturesVar <- "BufferClimateLandUse"
      
    }
    
    if(Pipeline == "B"){
      
      CurrentVar <- "Climate"
      FuturesVar <- "BufferClimate"
      
    }
    
    if(Pipeline == "C"){
      
      CurrentVar <- "ClimateLandUse"
      FuturesVar <- "ClimateLandUse"
      
    }
    
    if(Pipeline == "D"){
      
      CurrentVar <- "Climate"
      FuturesVar <- "Climate"
      
    }
    
    IcebergAdjList[[Pipeline]] <- list()
    
    if(Pipeline%in%LETTERS[c(1,2)]){
      
      print("Getting values!")
      
      CurrentCDFList %>% map(CurrentVar) %>% 
        map(function(a) a*(AreaValues[-Sea])) %>% bind_cols() %>% as.data.frame() ->
        ValueDF
      
      print("Calculating overlap!")
      
      RangeAdj <- PairsWisely(Rasterstack = ValueDF, Area = T)
      
      saveRDS(RangeAdj, file = paste0("Iceberg Output Files/", "CurrentsRangeAdj", Pipeline,".rds"))
      
      IcebergAdjList[[Pipeline]]$Currents <- RangeAdj
      
    }else{
      
      IcebergAdjList[[Pipeline]]$Currents <- IcebergAdjList[[which(LETTERS == Pipeline)-2]]$Currents
      
    }
  }
}

# Futures ####

print("Doing the futures!")

FutureCDFList <- list()

FutureCDFList[1:length(Species)] <- list()

# FutureCDFList <- mclapply(1:length(Species), function(a){

for(a in 1:length(Species)){
  
  Sp = Species[a]
  
  print(FutureFiles[a])
  
  FutureCDFList[[a]] <-
    readRDS(FutureFiles[[Sp]]) %>% 
    as.matrix %>% 
    as.data.frame() %>% 
    dplyr::select(contains("Futures"), -starts_with("LandUse"))
  
}#, mc.preschedule = F, mc.cores = CORES)

names(FutureCDFList) <- Species

object.size(FutureCDFList)/(10^9)

for(Pipeline in LETTERS[1:4]){
  
  FuturesVar <- ifelse(Pipeline == "A", "BufferClimateLandUse", 
                       ifelse(Pipeline == "B", "BufferClimate", 
                              ifelse(Pipeline == "C","ClimateLandUse", 
                                     "Climate")))
  
  PredReps[2:(length(PredReps))] %>% lapply(function(a){
    
    FutureCDFList %>% map(paste0(FuturesVar,".", a)) %>% 
      map(function(b) b*AreaValues[-Sea]) %>% bind_cols() %>% as.data.frame() ->
      ValueDF
    
    RangeAdj <- PairsWisely(ValueDF, Area = T)
    
    saveRDS(RangeAdj, file = paste0("Iceberg Output Files/", a, "RangeAdj", Pipeline,".rds"))
    
    return(RangeAdj)
    
  }) -> IcebergAdjList[[Pipeline]][PredReps[2:length(PredReps)]]
}

IcebergAdjList <- IcebergAdjList[PipelineReps]

saveRDS(IcebergAdjList, file = paste0("Iceberg Output Files/","IcebergAdjList.rds"))

for(Pipeline in LETTERS[1:4]){
  
  print(Pipeline)
  
  CurrentSpecies <- rownames(IcebergAdjList[[Pipeline]][[1]])
  
  for(x in 2:length(IcebergAdjList[[Pipeline]])){
    
    NewAdj <- IcebergAdjList[[Pipeline]][[x]]
    InsertSpecies <- setdiff(CurrentSpecies, rownames(NewAdj))
    
    if(length(InsertSpecies)>0){
      
      NewAdj <- NewAdj %>% data.frame()
      NewAdj[InsertSpecies,] <- 0; NewAdj[,InsertSpecies] <- 0
      NewAdj <- NewAdj %>% as.matrix
      
      IcebergAdjList[[Pipeline]][[x]] <- NewAdj[CurrentSpecies, CurrentSpecies]
    }
  }
}

saveRDS(IcebergAdjList, file = paste0("Iceberg Output Files/","IcebergAdjList.rds"))

lapply(IcebergAdjList, function(a) sapply(a, range))
lapply(IcebergAdjList, function(a) sapply(a, dim))

