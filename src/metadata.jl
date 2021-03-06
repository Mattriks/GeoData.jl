"""
Supertype for all metadata wrappers.

These allow tracking the contents and origin of metadata. 
This can facilitate conversion between metadata types (for saving 
a file to a differenet format) or simply saving data back to the 
same file type with identical metadata.
"""
abstract type Metadata{K,V} <: AbstractDict{K,V} end

(::Type{T})() where T <: Metadata = T(Dict())

val(metadata::Metadata) = metadata.val

Base.get(metadata::Metadata, args...) = get(val(metadata), args...)
Base.getindex(metadata::Metadata, args...) = getindex(val(metadata), args...)
Base.setindex!(metadata::Metadata, args...) = setindex!(val(metadata), args...)
Base.keys(metadata::Metadata) = keys(val(metadata))
Base.iterate(metadata::Metadata, args...) = iterate(val(metadata), args...)
Base.IteratorSize(::Metadata{M}) where M = Base.IteratorSize(M)
Base.IteratorEltype(::Metadata{M}) where M = Base.IteratorEltype(M)
Base.eltype(::Metadata{M}) where M = eltype(M)
Base.length(metadata::Metadata) = length(val(metadata))


"""
Metadata wrappers to be attached to `Dimension`s.
"""
abstract type DimMetadata{K,V} <: Metadata{K,V} end

"""
Metadata wrappers to be attached to `AbstractGeoArrays`.
"""
abstract type ArrayMetadata{K,V} <: Metadata{K,V} end

"""
Metadata wrappers to be attached to `AbstractGeoStack`.
"""
abstract type StackMetadata{K,V} <: Metadata{K,V} end
