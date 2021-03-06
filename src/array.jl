
"""
`AbstractGeoArray` wraps an array (or location of an array) and metadata
about its contents. It may be memory ([`GeoArray`](@ref)) or disk-backed
([`NCDarray`](@ref), [`GDALarray`](@ref), [`GRDarray`](@ref)).

`AbstractGeoArray`s inherit from [`AbstractDimArray`]($DDarraydocs) 
from DimensionalData.jl. They can be indexed as regular Julia arrays or with 
DimensionalData.jl [`Dimension`]($DDdimdocs)s. They will plot as a heatmap in 
Plots.jl with correct coordinates and labels, even after slicing with 
`getindex` or `view`. `getindex` on a `AbstractGeoArray` will always return 
a memory-backed `GeoArray`.
"""
abstract type AbstractGeoArray{T,N,D,A} <: AbstractDimensionalArray{T,N,D,A} end

# Marker singleton for lazy loaded arrays, only used for broadcasting.
# Can be removed when DiskArrays.jl is used everywhere
struct LazyArray{T,N} <: AbstractArray{T,N} end

# Interface methods ###########################################################

"""
    missingval(x)

Returns the value representing missing data in the dataset """ function missingval end
missingval(x) = missing
missingval(A::AbstractGeoArray) = A.missingval

"""
    crs(x)

Get the crs projection of a dim or for the `Lat`/`Lon` dims of an array.
"""
function crs end
crs(A::AbstractGeoArray) =
    if hasdim(A, Lat)
        crs(dims(A, Lat))
    elseif hasdim(A, Lon)
        crs(dims(A, Lon))
    else
        error("No Lat or Lon dimension, crs not available")
    end
crs(dim::Dimension) = crs(mode(dim), dim)

"""
    usercrs(x)

Get the user facing crs projection of a [`Projected`](@ref) mode 
dim or for the `Lat`/`Lon` dims of an array.

This is used to convert [`Selector`]($DDselectordocs) values form the user defined 
projection to the underlying projection, and to show plot axes in the user projection.
"""
function usercrs end
usercrs(A::AbstractGeoArray) =
    if hasdim(A, Lat)
        usercrs(dims(A, Lat))
    elseif hasdim(A, Lon)
        usercrs(dims(A, Lon))
    else
        error("No Lat or Lon dimension, usercrs not available")
    end
usercrs(dim::Dimension) = usercrs(mode(dim), dim)

"""
    dimcrs(x)

Get the index crs projection of a [`Converted`](@ref) mode dim or 
for the `Lat`/`Lon` dims of an array.

This is used for NetCDF and other formats where the underlying projection 
of the data may  be different to what is contained in the vector index.
"""
function dimcrs end
dimcrs(A::AbstractGeoArray) =
    if hasdim(A, Lat)
        dimcrs(dims(A, Lat))
    elseif hasdim(A, Lon)
        dimcrs(dims(A, Lon))
    else
        error("No Lat or Lon dimension, dimcrs not available")
    end
dimcrs(dim::Dimension) = dimcrs(mode(dim), dim)

# DimensionalData methods

units(A::AbstractGeoArray) = getmeta(A, :units, nothing)

# Rebuild all types of AbstractGeoArray as GeoArray
rebuild(A::AbstractGeoArray, data, dims::Tuple, refdims, name, metadata, missingval=missingval(A)) =
    GeoArray(data, dims, refdims, name, metadata, missingval)
rebuild(A::AbstractGeoArray; data=data(A), dims=dims(A), refdims=refdims(A), name=name(A), metadata=metadata(A), missingval=missingval(A)) =
    GeoArray(data, dims, refdims, name, metadata, missingval)

Base.parent(A::AbstractGeoArray) = data(A)


"""
Abstract supertype for all memory-backed GeoArrays where the data is an array.
"""
abstract type MemGeoArray{T,N,D,A} <: AbstractGeoArray{T,N,D,A} end


"""
Abstract supertype for all disk-backed GeoArrays.
For these the data is lazyily loaded from disk.
"""
abstract type DiskGeoArray{T,N,D,A} <: AbstractGeoArray{T,N,D,A} end

filename(A::DiskGeoArray) = A.filename

"""
    data(f, A::DiskGeoArray)

Run method `f` on the data source object for A, as passed by the
`withdata` method for the array. The only requirement of the
object is that it has an `Array` method that returns the data as an array.
"""
data(A::DiskGeoArray) = withsourcedata(Array, A)

# Base methods

Base.size(A::DiskGeoArray) = A.size

Base.getindex(A::DiskGeoArray, i1::StandardIndices, i2::StandardIndices, I::StandardIndices...) =
    rebuildgetindex(A, i1, i2, I...)
Base.getindex(A::DiskGeoArray, i1::Integer, i2::Integer, I::Vararg{<:Integer}) =
    rawgetindex(A, i1, i2, I...)
# Linear indexing returns Array
Base.@propagate_inbounds Base.getindex(A::DiskGeoArray, i::Union{Colon,AbstractVector{<:Integer}}) =
    rawgetindex(A, i)
# Exempt 1D DimArrays
Base.@propagate_inbounds Base.getindex(A::DiskGeoArray{<:Any,1}, i::Union{Colon,AbstractVector{<:Integer}}) =
    rebuildgetindex(A, i)

rawgetindex(A, I...) =
    withsourcedata(A) do data
        readwindowed(data, I...)
    end

rebuildgetindex(A, I...) =
    withsourcedata(A) do data
        dims_, refdims_ = slicedims(dims(A), refdims(A), I)
        data = readwindowed(data, I...)
        rebuild(A, data, dims_, refdims_)
    end

Base.write(A::T) where T <: DiskGeoArray = write(filename(A), A)
Base.write(filename::AbstractString, A::T) where T <: DiskGeoArray =
    write(filename, T, A)


# Concrete implementation ######################################################

"""
    GeoArray(A::AbstractArray{T,N}, dims::Tuple;
             refdims=(), name=Symbol(""), metadata=nothing, missingval=missing)
    GeoArray(A::AbstractArray{T,N}; 
             dims, refdims=(), name=Symbol(""), metadata=nothing, missingval=missing)
    GeoArray(A::AbstractGeoArray; [data=data(A), dims=dims(A), refdims=refdims(A),
             name=name(A), metadata=metadata(A), missingval=missingval(A)]) =

A generic, memory-backed spatial array type. All [`AbstractGeoArray`](@ref) are
converted to `GeoArray` when indexed or otherwise transformed.

# Keyword Arguments 

- `name`: `Symbol` name for the array.
- `dims`: `Tuple` of `Dimension`s for the array.
- `refdims`: `Tuple of` position `Dimension`s the array was sliced from, 
  defaulting to `()`.
- `missingval`: Value reprsenting missing values, defaulting to `missing`.
  can be passed it.
- `metadata`: [`Metadata`](@ref) object for the array, or `nothing`. 

## Example

```julia
A = GRDarray(gdalarray; name="surfacetemp")
# Select Australia using lat/lon coords, whatever the crs is underneath.
A[Lat(Between(-10, -43), Lon(Between(113, 153)))
```
"""
struct GeoArray{T,N,D<:Tuple,R<:Tuple,A<:AbstractArray{T,N},Na<:Symbol,Me,Mi} <: MemGeoArray{T,N,D,A}
    data::A
    dims::D
    refdims::R
    name::Na
    metadata::Me
    missingval::Mi
end
GeoArray(A::AbstractArray, dims, refdims, name::String, metadata, missingval=missing) = begin
    @warn "The GeoArray `name` field is now a Symbol"
    GeoArray(A, dims, refdims, Symbol(name), metadata, missingval)
end
@inline GeoArray(A::AbstractArray, dims::Tuple;
                 refdims=(), name=Symbol(""), metadata=nothing, missingval=missing) =
    GeoArray(A, formatdims(A, dims), refdims, name, metadata, missingval)
@inline GeoArray(A::AbstractArray; dims, refdims=(), name=Symbol(""), metadata=nothing, missingval=missing) =
    GeoArray(A, formatdims(A, dims), refdims, name, metadata, missingval)
@inline GeoArray(A::AbstractGeoArray; data=data(A), dims=dims(A), refdims=refdims(A),
                 name=name(A), metadata=metadata(A), missingval=missingval(A)) =
    GeoArray(data, dims, refdims, name, metadata, missingval)

Base.@propagate_inbounds Base.setindex!(A::GeoArray, x, I::Vararg{DimensionalData.StandardIndices}) =
    setindex!(data(A), x, I...)

Base.convert(::Type{GeoArray}, array::AbstractGeoArray) = GeoArray(array)
