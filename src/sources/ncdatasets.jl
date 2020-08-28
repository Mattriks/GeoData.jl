using .NCDatasets

export NCDarray, NCDstack, NCDdimMetadata, NCDarrayMetadata, NCDstackMetadata

"""
    NCDdimMetadata(val::Dict)

[`Metadata`](@ref) wrapper for [`NCDarray`](@ref) dimensions.
"""
struct NCDdimMetadata{K,V} <: DimMetadata{K,V}
    val::Dict{K,V}
end

"""
    NCDarrayMetadata(val::Dict)

[`Metadata`](@ref) wrapper for [`NCDarray`](@ref) metadata.
"""
struct NCDarrayMetadata{K,V} <: ArrayMetadata{K,V}
    val::Dict{K,V}
end

"""
    NCDstackMetadata(val::Dict)

[`Metadata`](@ref) wrapper for [`NCDarray`](@ref) metadata.
"""
struct NCDstackMetadata{K,V} <: StackMetadata{K,V}
    val::Dict{K,V}
end

const UNNAMED_NCD_KEY = "unnamed"


# Utils ########################################################################

ncread(f, path::String) = NCDatasets.Dataset(f, path)

nondimkeys(dataset) = begin
    dimkeys = keys(dataset.dim)
    removekeys = if "bnds" in dimkeys
        dimkeys = setdiff(dimkeys, ("bnds",))
        boundskeys = map(k -> dataset[k].attrib["bounds"], dimkeys)
        union(dimkeys, boundskeys)
    else
        dimkeys
    end
    setdiff(keys(dataset), removekeys)
end

# Add a var array to a dataset before writing it.
ncwritevar!(dataset, A::AbstractGeoArray{T,N}) where {T,N} = begin
    A = reorderindex(A, Forward()) |>
        a -> reorderrelation(a, Forward())
    if ismissing(missingval(A))
        # TODO default _FillValue for Int?
        fillvalue = get(metadata(A), "_FillValue", NaN)
        A = replace_missing(A, convert(T, fillvalue))
    end
    # Define required dim vars
    for dim in dims(A)
        key = lowercase(name(dim))
        haskey(dataset.dim, key) && continue
        
        index = ncshiftindex(dim)

        if dim isa Lat || dim isa Lon 
            dim = convertmode(Converted, dim) 
        end
        md = metadata(dim)
        attribvec = [] #md isa Nothing ? [] : [val(md)...]
        defDim(dataset, key, length(index))
        println("        key: \"", key, "\" of type: ", eltype(index))
        defVar(dataset, key, index, (key,); attrib=attribvec)
    end
    # TODO actually convert the metadata type
    attrib = if metadata isa NCDarrayMetadata
        deepcopy(val(metadata(A)))
    else
        Dict()
    end
    # Remove stack metdata if it is attached
    pop!(attrib, "dataset", nothing)
    # Set missing value
    if !ismissing(missingval(A))
        try
            fv = convert(T, missingval(A))
            attrib["_FillValue"] = fv
        catch
            @warn "`missingval` $(missingval(A)) was invalid for data of type $T."
        end
    end
    key = if name(A) == ""
        UNNAMED_NCD_KEY
    else
        name(A) 
    end
    println("        key: \"", key, "\" of type: ", T)
    dimnames = lowercase.(name.(dims(A)))
    attribvec = [attrib...]
    var = defVar(dataset, key, eltype(A), dimnames; attrib=attribvec)

    var[:] = data(A)
end

ncshiftindex(dim::Dimension) = ncshiftindex(mode(dim), dim)
ncshiftindex(mode::AbstractSampled, dim::Dimension) =
    if span(mode) isa Regular
        if dim isa TimeDim 
            if eltype(dim) isa Dates.AbstractDateTime
                val(dim)
            else
                shiftindexloci(Start(), dim)
            end
        else
            shiftindexloci(Center(), dim)
        end
    else
        dim
    end |> val
ncshiftindex(mode::IndexMode, dim::Dimension) = val(dim)

# CF standards don't enforce dimension names.
# But these are common, and should take care of most dims.
const dimmap = Dict("lat" => Lat,
                    "latitude" => Lat,
                    "lon" => Lon,
                    "long" => Lon,
                    "longitude" => Lon,
                    "time" => Ti,
                    "lev" => Vert,
                    "level" => Vert,
                    "vertical" => Vert,
                    "x" => X,
                    "y" => Y,
                    "z" => Z,
                   )

# Array ########################################################################
"""
    NCDarray(filename::AbstractString; name=nothing, refdims=(),
             dims=nothing, metadata=nothing, crs=EPSG(4326), dimcrs=EPSG(4326))

A [`DiskGeoArray`](@ref) that loads that loads NetCDF files lazily from disk.

The first non-dimension layer of the file will be used as the array. Dims are usually
detected as [`Lat`](@ref), [`Lon`](@ref), [`Ti`]($DDtidocs), and [`Vert`] or 
possibly `X`, `Y`, `Z` when detected. Undetected dims will use the generic `Dim{:name}`.

This is an incomplete implementation of the NetCDF standard. It will currently
handle simple files in lattitude/longitude projections, or projected formats
if you manually specify `crs` and `dimcrs`. How this is done may also change in 
future, including detecting and converting the native NetCDF projection format.

## Arguments

- `filename`: `String` pointing to a netcdf file.

## Keyword arguments

- `crs`: defaults to lat/lon `EPSG(4326)` but may be any `GeoFormat` like `WellKnownText`. 
  If the underlying data is in a different projection `crs` will need to be set to allow 
  `write` to a different file format. In future this may be detected automatically.
- `dimcrs`: The crs projection actually present in the Dimension index `Vector`, which 
  may be different to the underlying projection. Defaults to lat/lon `EPSG(4326)` but
  may be any crs `GeoFormat`.
- `name`: `String` name for the array. Will use array key if not supplied.
- `dims`: `Tuple` of `Dimension`s for the array. Detected automatically, but can be passed in.
- `refdims`: `Tuple of` position `Dimension`s the array was sliced from.
- `missingval`: Value reprsenting missing values. Detected automatically when possible, but 
  can be passed it.
- `metadata`: [`Metadata`](@ref) object for the array. Detected automatically as
  [`NCDarrayMetadata`](@ref), but can be passed in.

## Example

```julia
A = NCDarray("folder/file.ncd")
# Select Australia from the default lat/lon coords:
A[Lat(Between(-10, -43), Lon(Between(113, 153)))
```
"""
struct NCDarray{T,N,A,D<:Tuple,R<:Tuple,Na<:AbstractString,Me,Mi,S,K
               } <: DiskGeoArray{T,N,D,LazyArray{T,N}}
    filename::A
    dims::D
    refdims::R
    name::Na
    metadata::Me
    missingval::Mi
    size::S
    key::K
end
NCDarray(filename::AbstractString, key...; kwargs...) = begin
    isfile(filename) || error("File not found: $filename")
    ncread(dataset -> NCDarray(dataset, filename, key...; kwargs...), filename)
end
NCDarray(dataset::NCDatasets.Dataset, filename, key=nothing;
         crs=EPSG(4326),
         dimcrs=EPSG(4326),
         name=nothing,
         dims=nothing,
         refdims=(),
         metadata=nothing,
         missingval=missing,
        ) = begin
    keys_ = nondimkeys(dataset)
    key = key isa Nothing || !(string(key) in keys_) ? first(keys_) : string(key)
    var = dataset[key]
    dims = dims isa Nothing ? GeoData.dims(dataset, key, crs, dimcrs) : dims
    name = name isa Nothing ? string(key) : name
    metadata_ = metadata isa Nothing ? GeoData.metadata(var, GeoData.metadata(dataset)) : metadata
    size_ = map(length, dims)
    T = eltype(var)
    N = length(dims)

    NCDarray{T,N,typeof.((filename,dims,refdims,name,metadata_,missingval,size_,key))...
       }(filename, dims, refdims, name, metadata_, missingval, size_, key)
end

key(A::NCDarray) = A.key

# AbstractGeoArray methods

withsourcedata(f, A::NCDarray) =
    ncread(dataset -> f(dataset[string(key(A))]), filename(A))

# Base methods

Base.size(A::NCDarray) = A.size

"""
    Base.write(filename::AbstractString, ::Type{NCDarray}, s::AbstractGeoArray)

Write an NCDarray to a NetCDF file using NCDatasets.jl

Returns `filename`.
"""
Base.write(filename::AbstractString, ::Type, A::AbstractGeoArray) = begin
    meta = metadata(A)
    if meta isa Nothing
        dataset = NCDatasets.Dataset(filename, "c")
    else
        # Remove the dataset metadata
        stackmd = pop!(deepcopy(val(meta)), "dataset", Dict())
        dataset = NCDatasets.Dataset(filename, "c"; attrib=stackmd)
    end
    try
        println("    Writing netcdf...")
        ncwritevar!(dataset, A)
    finally
        close(dataset)
    end
    return filename
end

# Stack ########################################################################


"""
    NCDstack(filenames; keys, kwargs...)
    NCDstack(filenames...; keys, kwargs...)
    NCDstack(files::NamedTuple; refdims=(), window=(), metadata=nothing, childkwargs=())
    NCDstack(filename::String; refdims=(), window=(), metadata=nothing, childkwargs=())

A lazy [`AbstractGeoStack`](@ref) that uses NCDatasets.jl to load NetCDF files. 
Can load a single multi-layer netcdf file, or multiple single-layer netcdf 
files. In multi-file mode it returns a regular `GeoStack` with a `childtype` 
of [`NCDarray`](@ref).

Indexing into `NCDstack` with layer keys (`Symbol`s) returns a [`GeoArray`](@ref). 
Dimensions are usually detected as [`Lat`](@ref), [`Lon`](@ref), [`Ti`]($DDtidocs), 
and [`Vert`] or `X`, `Y`, `Z` when detected. Undetected dims use the generic `Dim{:name}`.

# Arguments

- `filename`: `Tuple` or `Vector` or splatted arguments of `String`,
  or single `String` path, to NetCDF files. 

# Keyword arguments

- `keys`: Used as stack keys when a `Tuple`, `Vector` or splat of filenames are passed in.
  These default to the first non-dimension data key in each NetCDF file.
- `refdims`: Add dimension position array was sliced from. Mostly used programatically.
- `window`: A `Tuple` of `Dimension`/`Selector`/indices that will be applied to the 
  contained arrays when they are accessed.
- `metadata`: A [`StackMetadata`](@ref) object.
- `childkwargs`: A `NamedTuple` of keyword arguments to pass to the 
  [`NCDarray`](@ref) constructor.

# Examples

```julia
stack = NCDstack(filename; window=(Lat(Between(20, 40),))
# Or
stack = NCDstack([fn1, fn1, fn3, fn4])
# And index with a layer key
stack[:soiltemp]
```
"""
struct NCDstack{T,R,W,M,K} <: DiskGeoStack{T}
    filename::T
    refdims::R
    window::W
    metadata::M
    childkwargs::K
end
NCDstack(filename::AbstractString;
         refdims=(),
         window=(),
         metadata=ncread(metadata, filename),
         childkwargs=()) =
    NCDstack(filename, refdims, window, metadata, childkwargs)
# These actually return a GeoStack
NCDstack(filenames...; kwargs...) = NCDstack(filenames; kwargs...)
NCDstack(filenames::Union{Tuple,Vector}, keys=ncfilenamekeys(filenames); kwargs...) =
    NCDstack(NamedTuple{keys}(filenames); kwargs...)
NCDstack(files::NamedTuple;
         refdims=(),
         window=(),
         metadata=nothing,
         childkwargs=()) =
    GeoStack(NamedTuple{keys}(filenames), refdims, window, metadata, 
             childtype=NCDarray, childkwargs)

ncfilenamekeys(filenames) = cleankeys(ncread(ds -> first(nondimkeys(ds)), fn) for fn in filenames)

childtype(::NCDstack) = NCDarray
childkwargs(stack::NCDstack) = stack.childkwargs
crs(stack::NCDarray) = get(childkwargs(stack), :crs, EPSG(4326))
dimcrs(stack::NCDarray) = get(childkwargs(stack), :dimcrs, nothing)

# AbstractGeoStack methods
withsource(f, ::Type{NCDarray}, path::AbstractString, key=nothing) = ncread(f, path)
withsourcedata(f, ::Type{NCDarray}, path::AbstractString, key) =
    ncread(d -> f(d[string(key)]), path)

# Override the default to get the dims of the specific key,
# and pass the crs and dimscrs from the stack
dims(stack::NCDstack, dataset, key::Key) = 
    dims(dataset, key, crs(stack), dimcrs(stack))

missingval(stack::NCDstack) = missing

# Base methods

Base.keys(stack::NCDstack{<:AbstractString}) =
    cleankeys(ncread(nondimkeys, getsource(stack)))

"""
    Base.write(filename::AbstractString, ::Type{NCDstack}, s::AbstractGeoStack)

Write an NCDstack to a single netcdf file, using NCDatasets.jl.

Currently [`DimMetadata`](@ref) is not handled, and [`ArrayMetadata`](@ref) 
from other [`AbstractGeoArray`](@ref) @types is ignored.
"""
Base.write(filename::AbstractString, ::Type{<:NCDstack}, s::AbstractGeoStack) = begin
    dataset = NCDatasets.Dataset(filename, "c"; attrib=val(metadata(s)))
    try
        map(key -> ncwritevar!(dataset, s[key]), keys(s))
    finally
        close(dataset)
    end
end

# DimensionalData methods for NCDatasets types ###############################

dims(dataset::NCDatasets.Dataset, key::Key, crs=nothing, dimcrs=nothing) = begin
    v = dataset[string(key)]
    dims = []
    for (i, dimname) in enumerate(NCDatasets.dimnames(v))
        if haskey(dataset, dimname)
            dvar = dataset[dimname]
            # Find the matching dimension constructor. If its an unknown name use
            # the generic Dim with the dim name as type parameter
            dimtype = get(dimmap, dimname, Dim{Symbol(dimname)})
            index = dvar[:]
            mode = _ncdmode(index, dimtype, crs, dimcrs)
            meta = NCDdimMetadata(Dict{String,Any}(dvar.attrib))

            # Add the dim containing the dimension var array
            push!(dims, dimtype(index, mode, meta))
        else
            # The var doesn't exist. Maybe its `complex` or some other marker,
            # so make it a custom `Dim` with `NoIndex`
            push!(dims, Dim{Symbol(dimname)}(1:size(v, i), NoIndex(), nothing))
        end
    end
    (dims...,)
end

_ncdmode(index::AbstractArray{<:Number}, dimtype, crs, dimcrs) = begin
    # Assume the locus is at the center of the cell if boundaries aren't provided.
    # http://cfconventions.org/cf-conventions/cf-conventions.html#cell-boundaries
    # Unless its a time dimension.
    order = _ncdorder(index)
    span = _ncdspan(index, order)
    # Using Points for time is a short-term fix as we can't yet get the interval 
    # length from NetCDF metadata. Interval size is required to have `Regular` intervals 
    # where the CF time at center of interval standard will work. Using `Irregular` where 
    # bounds are +/- half the distance between points will not give accurate months.
    sampling = dimtype <: TimeDim ? Points() : Intervals(Center())
    if dimtype in (Lat, Lon)
        Converted(order, span, sampling, crs, dimcrs)
    else
        Sampled(order, span, sampling)
    end
end
_ncdmode(index::AbstractArray{<:Dates.AbstractTime}, dimtype, crs, dimcrs) = begin
    order = _ncdorder(index)
    span = Irregular(
        if length(index) > 1
            # Use the second last interval to guess the last interval
            # This is a bit of a hack: we need to parse units to resolve it.
            if isrev(indexorder(order))
                index[end], index[1] + (index[1] - index[2])
            else
                index[1], index[end] + (index[end] - index[end - 1])
            end
        else
            index[1], index[1]
        end
    )
    sampling = Intervals(Start())
    Sampled(order, span, sampling)
end
_ncdmode(index, dimtype, crs, dimcrs) = Categorical()

_ncdorder(index) = index[end] > index[1] ? Ordered(Forward(), Forward(), Forward()) :
                                           Ordered(Reverse(), Reverse(), Forward())

_ncdspan(index, order) = begin
    step = index[2] - index[1]
    for i in 2:length(index) -1
        if !(index[i+1] - index[i] ≈ step)
            bounds = if length(index) > 1
                beginhalfcell = abs((index[2] - index[1]) * 0.5)
                endhalfcell = abs((index[end] - index[end-1]) * 0.5)
                if isrev(indexorder(order))
                    index[end] - endhalfcell, index[1] + beginhalfcell
                else
                    index[1] - beginhalfcell, index[end] + endhalfcell
                end
            else
                index[1], index[1]
            end
            return Irregular(bounds)
        end
    end
    return Regular(step)
end

metadata(dataset::NCDatasets.Dataset) = NCDstackMetadata(Dict{String,Any}(dataset.attrib))
metadata(dataset::NCDatasets.Dataset, key::Key) = metadata(dataset[string(key)])
metadata(var::NCDatasets.CFVariable) = NCDarrayMetadata(Dict{String,Any}(var.attrib))
metadata(var::NCDatasets.CFVariable, stackmetadata::NCDstackMetadata) = begin
    md = metadata(var)
    md["dataset"] = stackmetadata
    md
end

missingval(var::NCDatasets.CFVariable) = missing

# Direct loading: better memory handling?
# readwindowed(A::NCDatasets.CFVariable) = readwindowed(A, axes(A)...)
# readwindowed(A::NCDatasets.CFVariable, i, I...) = begin
#     var = A.var
#     indices = to_indices(var, (i, I...))
#     shape = Base.index_shape(indices...)
#     dest = Array{eltype(var),length(shape)}(undef, map(length, shape)...)
#     NCDatasets.load!(var, dest, indices...)
#     dest
# end
