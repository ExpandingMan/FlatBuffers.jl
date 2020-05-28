# TODO decide what to do about the reinterprets

struct VTable{T} <: AbstractVector{Int16}
    nbytes::Int16
    table_nbytes::Int16
    slots::Vector{Int16}
end

function VTable{T}(buf::AbstractVector{UInt8}, start::Integer) where {T}
    vnbytes, tnbytes = reinterpret(Int16, @view buf[start:(start+3)])
    soffs = slotoffsets(T)
    slots = reinterpret(Int16, @view buf[(start+soffs[1]):(start+soffs[end]+1)])
    VTable{T}(vnbytes, tnbytes, slots)
end

Base.IndexStyle(::Type{<:VTable}) = IndexLinear()
Base.size(vt::VTable) = size(vt.slots)
Base.getindex(vt::VTable, i::Integer) = getindex(vt.slots, i)

nbytes(vt::VTable) = vt.nbytes


struct Table{T,V<:AbstractVector{UInt8}}
    buffer::V
    start::Int
    vtable_start::Int32

    vtable::VTable{T}  # fully constructed already
end

function Table{T}(buf::AbstractVector{UInt8}, start::Integer) where {T}
    vtstart = start - reinterpret(Int32, @view buf[start:(start+3)])[1]
    Table{T,typeof(buf)}(buf, start, vtstart, VTable{T}(buf, vtstart))
end

# construct table from field of other table
Table{U}(t::Table{T}, i::Integer) where {T,U} = Table{U}(t.buffer, fieldstart(t, i)+pointerfield(t,i))
Table{U}(t::Table{T}, s::Symbol) where {T,U} = Table{U}(t, Base.fieldindex(T, s))

Table(t::Table{T}, i::Integer) where {T} = Table{fieldtype(T,i)}(t, i)
Table(t::Table{T}, s::Symbol) where {T} = Table{fieldtype(T,s)}(t, i)

default(t::Table{T}, i::Integer) where {T} = default(T, i)

nbytes(t::Table) = t.vtable.table_nbytes

tablestart(t::Table) = t.start
tableend(t::Table) = t.start + nbytes(t) - 1

Base.view(t::Table) = view(t.buffer, tablestart(t):tableend(t))

isdefault(t::Table, i::Integer) = i > length(t.vtable) || iszero(t.vtable[i])

fieldstart(t::Table, i::Integer) = tablestart(t) + t.vtable[i]

function fieldend(t::Table{T}, i::Integer) where {T}
    U = fieldtype(T, i)
    # Int32 is default offset used for all references (I think)
    s = U <: BitsType ? sizeof(U) : sizeof(Int32)
    tablestart(t) + t.vtable[i] + s - 1
end

function fielddatastart(t::Table, i::Integer)
    fs = fieldstart(t, i)
    fs + reinterpret(Int32, @view t.buffer[fs:fieldend(t, i)])[1]
end

function bitsfield(::Type{U}, t::Table{T}, i::Integer) where {T,U}
    # no default check here since this is intended to be used nefariously
    reinterpret(U, @view t.buffer[fieldstart(t, i):(fieldstart(t,i)+sizeof(U)-1)])[1]
end

function bitsfield(t::Table{T}, i::Integer) where {T}
    isdefault(t, i) && return default(t, i)
    reinterpret(fieldtype(T, i), @view t.buffer[fieldstart(t, i):fieldend(t, i)])[1]
end

pointerfield(t::Table, i::Integer) = bitsfield(Int32, t, i)

uniontypefield(t::Table, i::Integer) = bitsfield(UInt8, t, i)

enumfield(t::Table{T}, ::Type{<:Enum{U}}, i::Integer) where {T,U} = U(bitsfield(t, i))

function bitsvectorfield(t::Table, ::Type{<:AbstractVector{U}}, i::Integer) where {U}
    isdefault(t, i) && return default(t, i)
    s = fielddatastart(t, i)
    n = reinterpret(Int32, @view t.buffer[s:(s+3)])[1]
    Vector(reinterpret(U, @view t.buffer[(s+4):(s+3 + n*sizeof(U))]))
end

structfield(t::Table, ::Type{U}, i::Integer) where {U} = readstruct(U, t.buffer, fieldstart(t, i))

# TODO will this break for unicode strings?  hopefully they are using nbytes
stringfield(t::Table, i::Integer) = String(bitsvectorfield(t, Vector{UInt8}, i))

function field(t::Table{T}, i::Integer)::fieldtype(T, i) where {T}
    U = fieldtype(T, i)
    # TODO how fast is this?
    if U <: BitsType
        bitsfield(t, i)
    elseif U <: Enum
        enumfield(t, U, i)
    elseif isstruct(U)
        structfield(t, U, i)
    elseif U <: AbstractVector{<:BitsType}
        bitsvectorfield(t, U, i)
    elseif U <: AbstractString
        stringfield(t, i)
    elseif BufferType(U) ≡ TableType()
        Table(t, i)
    elseif BufferType(U) ≡ UnionType()
        V = uniontype(U, uniontypefield(t, i-1)+1)
        # TODO obviously this needs to work on any type
        # TODO also, this part in particular is slow as fuck!!!
        Table{V}(t, i)()
    else
        throw(ErrorException("what the fuck is this type?"))
    end
end
field(t::Table{T}, s::Symbol) where {T} = field(t, Base.fieldindex(T, s))

# NOTE: need both methods to resolve type ambiguity
Base.getindex(t::Table, i::Integer) = field(t, i)
Base.getindex(t::Table, s::Symbol) = field(t, s)
(t::Table{T})() where {T} = T((field(t, i) for i ∈ 1:length(fieldtypes(T)))...)

