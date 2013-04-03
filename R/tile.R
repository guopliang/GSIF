# Purpose        : tile points, lines, polygons or rasters based on a polygon map;
# Maintainer     : Tomislav Hengl (tom.hengl@wur.nl)
# Contributions  : ; 
# Dev Status     : Pre-Alpha
# Note           : it works together with FWTools and SAGA GIS if requested;

## create a tiling system (Polygon map):
setMethod("getSpatialTiles", signature(obj = "Spatial"), function(obj, block.x, block.y = block.x, overlap.percent = 0, limit.bbox = TRUE, return.SpatialPolygons = TRUE){

  if(overlap.percent<0){
    stop("'overlap.percent' argument must be a positive number")
  }

  ## check the input bbox:
  if(!(ncol(obj@bbox)==2&nrow(obj@bbox)==2&obj@bbox[1,1]<obj@bbox[1,2]&obj@bbox[2,1]<obj@bbox[2,2])){
    stop("Bounding box with two-column matrix required; the first column has the minimum, the second the maximum values;\n rows represent the spatial dimensions required")
  }
  
  ## number of tiles:
  xn = ceiling(diff(obj@bbox[1,])/block.x)
  yn = ceiling(diff(obj@bbox[2,])/block.y)

  # number of tiles:
  message(paste("Generating", xn*yn, "tiles..."))  
  xminl = obj@bbox[1,1]
  yminl = obj@bbox[2,1]
  xmaxl = obj@bbox[1,1] + (xn-1) * block.x
  ymaxl = obj@bbox[2,1] + (yn-1) * block.y
  xminu = obj@bbox[1,1] + block.x
  yminu = obj@bbox[2,1] + block.y
  xmaxu = obj@bbox[1,1] + xn * block.x
  ymaxu = obj@bbox[2,1] + yn * block.y
  
  b.l <- expand.grid(KEEP.OUT.ATTRS=FALSE, xl=seq(xminl, xmaxl, by=block.x), yl=seq(yminl, ymaxl, by=block.y))
  b.u <- expand.grid(KEEP.OUT.ATTRS=FALSE, xu=seq(xminu, xmaxu, by=block.x), yu=seq(yminu, ymaxu, by=block.y))
  btiles <- cbind(b.l, b.u)
  # expand if necessary:
  btiles$xl <- btiles$xl - block.x * overlap.percent/100
  btiles$yl <- btiles$yl - block.y * overlap.percent/100
  btiles$xu <- btiles$xu + block.x * overlap.percent/100
  btiles$yu <- btiles$yu + block.y * overlap.percent/100
  
  if(limit.bbox == TRUE){
    ## fix min max coordinates:
    btiles$xl <- ifelse(btiles$xl < obj@bbox[1,1], obj@bbox[1,1], btiles$xl)
    btiles$yl <- ifelse(btiles$yl < obj@bbox[2,1], obj@bbox[2,1], btiles$yl)  
    btiles$xu <- ifelse(btiles$xu > obj@bbox[1,2], obj@bbox[1,2], btiles$xu)
    btiles$yu <- ifelse(btiles$yu > obj@bbox[2,2], obj@bbox[2,2], btiles$yu)
  }

  if(return.SpatialPolygons == TRUE){
    ## get coordinates for each tile:
    coords.lst <- lapply(as.list(as.data.frame(t(as.matrix(btiles)))), function(x){matrix(c(x[1], x[1], x[3], x[3], x[1], x[2], x[4], x[4], x[2], x[2]), ncol=2, dimnames=list(paste("p", 1:5, sep=""), attr(obj@bbox, "dimnames")[[1]]))})

    ## create an object of class "SpatialPolygons"
    srl = lapply(coords.lst, Polygon)
    Srl = list()
  for(i in 1:length(srl)){ Srl[[i]] <- Polygons(list(srl[[i]]), ID=row.names(btiles)[i]) }
    pol = SpatialPolygons(Srl, proj4string=obj@proj4string)
  } else {
    pol = btiles
  }

  message(paste("Returning a list of tiles with", signif(overlap.percent, 3), "percent overlap"))
  return(pol)

})


## tile points:
.subsetTiles <- function(x, y, block.x, ...){
    if(missing(y)){
      y <- getSpatialTiles(x, block.x = block.x, ...) 
    }
    ## subset by tiles:
    ov <- over(x, y)
    t.lst <- sapply(slot(y, "polygons"), slot, "ID")
    bbox.lst <- lapply(slot(y, "polygons"), bbox)
    message(paste('Subseting object of class \"', class(x), '\"...', sep=""))
    x.lst <- list()
    for(i in 1:length(y)){
      sel <- ov == t.lst[i]
      if(length(sel)>0&!all(is.na(sel))){
        if(!all(sel==FALSE)){
          x.lst[[i]] <- subset(x, subset=sel)
          x.lst[[i]]@bbox <- bbox.lst[[i]]
        }
      }
    }
    return(x.lst)
}

setMethod("tile", signature(x = "SpatialPointsDataFrame"), .subsetTiles)
setMethod("tile", signature(x = "SpatialPixelsDataFrame"), .subsetTiles)

## tile using OGR2OGR function:
.clipTiles <- function(x, y, block.x, tmp.file = FALSE, program, show.output.on.console = FALSE, ...){
    
    if(missing(program)){
      program = .ogr2ogr()
    }   
    
    if(missing(y)){
      y <- getSpatialTiles(x, block.x = block.x, return.SpatialPolygons = FALSE, ...) 
    }
    
    ## write to shape file:
    if(tmp.file==TRUE){
      tf <- tempfile()
    } else {
      tf <- normalizeFilename(deparse(substitute(x, env = parent.frame())))
    } 
    if(class(x)=="SpatialPolygonsDataFrame"){ writePolyShape(x, set.file.extension(tf, ".shp")) }
    if(class(x)=="SpatialLinesDataFrame"){ writeLinesShape(x, set.file.extension(tf, ".shp")) }    

    ## clip by tiles:
    x.lst <- list()
    message("Clipling lines using 'ogr2ogr'...")
    for(j in 1:nrow(y)){
      if(tmp.file==TRUE){
        outname <- tempfile()
      } else {
        outname <- paste(normalizeFilename(deparse(substitute(x, env = parent.frame()))), j, sep="_")
      }
      if(class(x)=="SpatialPolygonsDataFrame"){
        try(system(paste(program, '-where \"OGR_GEOMETRY=\'Polygon\'\" -f \"ESRI Shapefile\"', set.file.extension(outname, ".shp"), set.file.extension(tf, ".shp"), '-clipsrc',  y[j,1], y[j,2], y[j,3], y[j,4], '-skipfailures'), show.output.on.console = show.output.on.console))
        try(x.lst[[j]] <- readShapePoly(normalizePath(set.file.extension(outname, ".shp")), proj4string=x@proj4string))
      }
      if(class(x)=="SpatialLinesDataFrame"){
        try(system(paste(program, '-where \"OGR_GEOMETRY=\'Linestring\'\" -f \"ESRI Shapefile\"', set.file.extension(outname, ".shp"), set.file.extension(tf, ".shp"), '-clipsrc',  y[j,1], y[j,2], y[j,3], y[j,4], '-skipfailures'), show.output.on.console = show.output.on.console))
        try(x.lst[[j]] <- readShapeLines(normalizePath(set.file.extension(outname, ".shp")), proj4string=x@proj4string))
      }
    }
    return(x.lst)
}

setMethod("tile", signature(x = "SpatialPolygonsDataFrame"), .clipTiles)
setMethod("tile", signature(x = "SpatialLinesDataFrame"), .clipTiles)

## tile external raster:
setMethod("tile", signature(x = "RasterLayer"), function(x, y, block.x, tmp.file = FALSE, program, show.output.on.console = FALSE, ...){

  if(filename(x)==""){
    stop("Function applicable only to 'RasterLayer' objects linking to external raster files")
  }

  if(missing(program)){
    if(.Platform$OS.type == "windows") {
      fw.dir = .FWTools.path()        
      program = shQuote(shortPathName(normalizePath(file.path(fw.dir, "bin/gdalwarp.exe"))))
    } else {
      program = "gdalwarp"
    }
  }
  
  if(missing(y)){
      b <- bbox(x)
      pol <- SpatialPolygons(list(Polygons(list(Polygon(matrix(c(b[1,1], b[1,1], b[1,2], b[1,2], b[1,1], b[2,1], b[2,2], b[2,2], b[2,1], b[2,1]), ncol=2))), ID="1")), proj4string=CRS(proj4string(x)))
      y <- getSpatialTiles(pol, block.x = block.x, return.SpatialPolygons = FALSE, ...) 
  }
  ## gdalwarp by tiles:
  x.lst <- list()
  message("Clipling raster object using 'gdalwarp'...")
  for(j in 1:nrow(y)){
      if(tmp.file==TRUE){
        outname <- tempfile()
      } else {
        outname <- paste(normalizeFilename(deparse(substitute(x, env = parent.frame()))), j, sep="_")
      }
      try(system(paste(program, shortPathName(normalizePath(filename(x))), set.file.extension(outname, ".tif"), '-te',  y[j,1], y[j,2], y[j,3], y[j,4]), show.output.on.console = show.output.on.console))
      try(x.lst[[j]] <- raster(set.file.extension(outname, ".tif")))
  }
  return(x.lst)    
    
})


# end of script;