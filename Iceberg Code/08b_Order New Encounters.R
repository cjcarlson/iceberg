
# Order-specific intersects ####

# Rscript "Final Iceberg Code/6b_Order New Encounters.R"

library(tidyverse); library(Matrix); library(parallel); library(mgcv); library(SpRanger); library(raster)
library(sf); library(fasterize);library(ggregplot); library(igraph);library(maptools)

PredReps <- c("Currents", paste0("Futures", 1:4))
PipelineReps <- LETTERS[1:4]

AreaRaster <- raster("Iceberg Input Files/LandArea.asc")
AreaValues <- raster::values(AreaRaster)

IcebergAdjList <- readRDS(paste0("Iceberg Output Files/","IcebergAdjList.rds"))
NewEncountersList <- readRDS(paste0("Iceberg Output Files/","NewEncounters.rds"))
AllMammaldf <- readRDS(paste0("Iceberg Output Files/","AllMammaldf.rds"))

SpaceVars <- paste0(paste("Space", PredReps, sep = "."),rep(PipelineReps, each = length(PredReps)))
SharingVars <- paste0(paste("Sharing",PredReps, sep = "."), rep(PipelineReps, each = length(PredReps)))

names(SpaceVars) <- names(SharingVars) <- paste0(PredReps,rep(PipelineReps, each = length(PredReps)))

# Iceberg General Maps ####

GridList <- NEGridList <- list()

CORES = 65

t1 <- Sys.time()

# Blanks
blank <- matrix(0,360*2,720*2) # proper resolution
blank <- raster(blank)
extent(blank) <- c(-180,180,-90,90)
projection(blank) <- CRS("+proj=longlat +datum=WGS84")

UniversalBlank <- raster("Iceberg Input Files/UniversalBlank.tif")
Land = which(raster::values(UniversalBlank)==0)
Sea = which(is.na(raster::values(UniversalBlank)))

Species <- 
  paste0("Iceberg Input Files/GretCDF/Currents") %>% list.files() %>% str_remove(".rds$") %>%
  sort

paste0("Iceberg Input Files/GretCDF/Currents") %>% 
  list.files(full.names = T) ->
  CurrentFiles

paste0("Iceberg Input Files/GretCDF/Currents") %>% 
  list.files() %>% str_remove(".rds$") ->
  names(CurrentFiles)

paste0("Iceberg Input Files/GretCDF/Futures") %>% 
  list.files(full.names = T) ->
  FutureFiles

paste0("Iceberg Input Files/GretCDF/Futures") %>% 
  list.files() %>% str_remove(".rds$") ->
  names(FutureFiles)

FutureCDFList <- list()

Species <- Species %>% sort %>% intersect(names(CurrentFiles)) #%>% intersect(names(FutureFiles))

AllNESpecies <- 
  
  NewEncountersList %>% unlist(recursive = F) %>% lapply(function(a){
    
    a %>% dplyr::select(Sp, Sp2) %>% unlist %>% unique
    
  }) %>% reduce(union) %>% sort

Species <- intersect(Species, AllNESpecies)

# Adding bat exception ####

Panth1 <- read.delim("data/PanTHERIA_1-0_WR05_Aug2008.txt") %>%
  dplyr::rename(Sp = MSW05_Binomial, hOrder = MSW05_Order, hFamily = MSW05_Family)
Panth1$Sp <- Panth1$Sp %>% str_replace(" ", "_")

Panth1 %>% filter(hOrder == "Chiroptera") %>% pull(Sp) %>%
  intersect(Species) ->
  BatSpecies

CurrentFiles <- CurrentFiles[Species]
FutureFiles <- FutureFiles[Species]

PipelineReps <- LETTERS[1:4]

print("Futures!")

FutureCDFList <- list()

Sharing <- AllMammaldf %>% 
  dplyr::select(Sp, Sp2, 
                starts_with("Sharing.Futures"))

# NewEncounters ####

print("New Encounters!")

FutureCDFList <- list()

for(i in Species){
  
  print(i)
  
  FutureCDFList[[i]] <- readRDS(FutureFiles[[i]]) %>% 
    as.matrix %>% 
    as.data.frame()
  
}

FuturesBase <- c(A = "BufferClimateLandUse",
                 B = "BufferClimate",
                 C = "ClimateLandUse",
                 D = "Climate")

# Looking at order-specific intersects #####

MammalOrders <- Panth1 %>% filter(Sp %in% Species) %>% pull(hOrder) %>% 
  unique %>% as.character()

lapply(MammalOrders, function(a){
  
  NewEncountersList %>% sapply(function(b){
    
    sapply(b, function(d){
      
      d %>% filter(hOrder.x == a|hOrder.y == a) %>% nrow
      
    })
    
  }) %>% reshape2::melt() %>% mutate(hOrder = a)
  
}) %>% bind_rows() -> NEList

ggplot(NEList, aes(Var1, Var2, fill = value, label = value)) + geom_tile() + coord_fixed() + facet_wrap(~hOrder)

NEList %>% filter(!hOrder == "Chiroptera") %>%
  ggplot(aes(Var1, Var2, fill = value, label = value)) + geom_tile() + coord_fixed() + facet_wrap(~hOrder)

# Order-specific new intersects! ####

MammalOrders <- MammalOrders %>% setdiff("Chiroptera")

for(Run in c("NoBat", "Bat")){
  
  for(i in MammalOrders){
    
    print(i)
    
    NewIntersectsManual <- FutureCDFList[[1]] %>% dplyr::select(X, Y)
    
    for(Pipeline in PipelineReps){
      
      print(Pipeline)
      
      for(x in 2:length(PredReps)){
        
        print(PredReps[x])
        
        NewEncounters <- NewEncountersList[[Pipeline]][[PredReps[x]]] %>%
          filter(hOrder.x == i|hOrder.y == i)
        
        if(Run == "NoBat"){
          
          NewEncounters <- NewEncounters %>% filter(!hOrder.x == "Chiroptera", !hOrder.y == "Chiroptera")
          
        }
        
        FutureCDFList %>%
          map(paste0(FuturesBase[Pipeline], ".", PredReps[x])) %>% 
          bind_cols %>% as.data.frame() ->
          ValueDF
        
        OverlapSums <- OverlapSharingSums <- DeltaOverlapSharing <- rep(0, nrow(ValueDF))
        
        for(y in 1:nrow(NewEncounters)){
          
          if(y %% 5000==0) print(y)
          
          Sp1 <- NewEncounters[y,"Sp"]
          Sp2 <- NewEncounters[y,"Sp2"]
          
          SubSums <- as.numeric(rowSums(ValueDF[,c(Sp1,Sp2)])>1)
          
          OverlapSums <- OverlapSums + SubSums
          # SubSumList[[paste0(Sp1,".",Sp2)]] <- SubSums
          
          OverlapSharingSums <- OverlapSharingSums +
            
            SubSums*NewEncounters[y, paste0("Sharing.",PredReps[x],Pipeline)]
          
          DeltaOverlapSharing <- DeltaOverlapSharing +
            
            SubSums*NewEncounters[y, paste0("DeltaSharing.",PredReps[x],Pipeline)]
          
        }
        
        NewIntersectsManual[,paste0("Overlap.",PredReps[x],Pipeline)] <-
          OverlapSums
        
        NewIntersectsManual[,paste0("OverlapSharing.",PredReps[x],Pipeline)] <-
          OverlapSharingSums
        
        NewIntersectsManual[,paste0("DeltaOverlapSharing.",PredReps[x],Pipeline)] <-
          DeltaOverlapSharing
        
        saveRDS(NewIntersectsManual, file = paste0("Iceberg Output Files/",i,Run,"NewIntersects.rds"))
        
      }
    }
  }
}