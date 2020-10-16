module GeoData

# Use the README as the module docs
@doc let
    path = joinpath(dirname(@__DIR__), "README.md")
    include_dependency(path)
    read(path, String)
end GeoData

using Missings,
      Mixers,
      RecipesBase,
      Reexport,
      Requires,
      Dates,
      Mmap,
      ProgressMeter

@reexport using DimensionalData, GeoFormatTypes

const DD = DimensionalData

using Base: tail
using DimensionalData: formatdims, slicedims, basetypeof,
      dims2indices, indexorder, arrayorder, relation, isrev, StandardIndices

import DimensionalData: val, data, dims, refdims, metadata, name, label, units,
       bounds, sel2indices, mode, order, locus, span, sampling, forwardorder,
       rebuild, rebuildsliced, modify

export Metadata, DimMetadata, ArrayMetadata, StackMetadata

export AbstractGeoArray, MemGeoArray, DiskGeoArray, GeoArray
export AbstractGeoStack, MemGeoStack, DiskGeoStack, DiskStack, GeoStack

export AbstractGeoSeries, GeoSeries

export Projected, Mapped

export missingval, boolmask, missingmask, replace_missing,
       aggregate, aggregate!, disaggregate, disaggregate!,
       crs, mappedcrs

export Lon, Lat, Vert, Band

# DimensionalData documentation urls
const DDdocs = "https://rafaqz.github.io/DimensionalData.jl/stable/api"
const DDdimdocs = joinpath(DDdocs, "#DimensionalData.Dimension")
const DDarraydocs = joinpath(DDdocs, "#DimensionalData.AbstractDimensionalArray")
const DDabssampleddocs = joinpath(DDdocs, "#DimensionalData.AbstractSampled")
const DDsampleddocs = joinpath(DDdocs, "#DimensionalData.Sampled")
const DDlocusdocs = joinpath(DDdocs, "#DimensionalData.Locus")
const DDselectordocs = joinpath(DDdocs, "#DimensionalData.Selector")
const DDtidocs = joinpath(DDdocs, "#DimensionalData.Ti")

include("dimensions.jl")
include("metadata.jl")
include("array.jl")
include("stack.jl")
include("series.jl")
include("utils.jl")
include("aggregate.jl")
include("methods.jl")
include("mode.jl")
include("sources/grd.jl")
include("plotrecipes.jl")

function __init__()
    @require HDF5="f67ccb44-e63f-5c2f-98bd-6dc0ccc4ba2f" begin
        # This section is for sources that rely on HDF5, not simply any HDF5.
        include("sources/smap.jl")
    end
    @require NCDatasets="85f8d34a-cbdd-5861-8df4-14fed0d494ab" begin
        include("sources/ncdatasets.jl")
    end
    @require ArchGDAL="c9ce4bd3-c3d5-55b8-8973-c0e20141b8c3" begin
        include("resample.jl")
        include("reproject.jl")
        include("sources/gdal.jl")
    end
end

end
