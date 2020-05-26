
isstruct(::Type{T}) where {T} = isconcretetype(T) && !T.mutable

struct StructFields{T,V<:AbstractVector{UInt8}}
    buffer::V
    start::Int
end

StructFields{T}(v::AbstractVector{UInt8}, start::Integer) where {T} = StructFields{T,typeof(v)}(v, start)

Base.length(sf::StructFields{T}) where {T} = length(fieldtypes(T))
Base.IteratorEltype(::StructFields) = Base.EltypeUnknown()

function Base.iterate(sf::StructFields{T}, (idx, i)=(sf.start, 1)) where {T}
    i > length(fieldtypes(T)) && return nothing
    U = fieldtype(T, i)
    idx2 = idx + sizeof(U)
    o = reinterpret(U, @view sf.buffer[idx:(idx2-1)])[1]
    o, (idx2, i+1)
end


function readstruct(::Type{T}, buf::AbstractVector{UInt8}, start::Integer) where {T}
    T(StructFields{T}(buf, start)...)    
end
