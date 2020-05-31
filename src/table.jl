# TODO decide what to do about the reinterprets

struct VTable{T,V<:AbstractVector{Int16}} <: AbstractVector{Int16}
    nbytes::Int16
    table_nbytes::Int16
    slots::V
end

function vtable_offsets_count(::Type{T}) where {T}
    soffs = slotoffsets(T)
    soffs, ((soffs[end] - 4) ÷ 2) + 1
end

function VTable{T}(buf::AbstractVector{UInt8}, start::Integer) where {T}
    vnbytes, tnbytes = reinterpret(Int16, @view buf[start:(start+3)])
    soffs, n = vtable_offsets_count(T)
    δ = ((start+soffs[1]):(start+soffs[end]+1))[1:min(2n, 2((vnbytes - 4) ÷ 2))]
    slots = reinterpret(Int16, @view buf[δ])
    VTable{T,typeof(slots)}(vnbytes, tnbytes, slots)
end

Base.IndexStyle(::Type{<:VTable}) = IndexLinear()
Base.size(vt::VTable) = size(vt.slots)
Base.getindex(vt::VTable, i::Integer) = getindex(vt.slots, i)

nbytes(vt::VTable) = vt.nbytes


struct Table{T,V<:AbstractVector{UInt8},VT<:VTable}
    buffer::V
    start::Int
    vtable_start::Int32

    vtable::VT  # fully constructed already
end

function Table{T}(buf::AbstractVector{UInt8}, start::Integer) where {T}
    vtstart = start - reinterpret(Int32, @view buf[start:(start+3)])[1]
    vt = VTable{T}(buf, vtstart)
    Table{T,typeof(buf),typeof(vt)}(buf, start, vtstart, vt)
end

readval(::Type{T}, t::Table, s::Integer) where {T} = readval(T, buffer(t), s)

VTable(t::Table) = getfield(t, :vtable)

const TableObject{T} = Union{T,Table{T}}

buffer(t::Table) = getfield(t, :buffer)

# construct table from field of other table
Table{U}(t::Table{T}, i::Integer) where {T,U} = Table{U}(buffer(t), fieldstart(t, i)+pointerfield(t,i))
Table{U}(t::Table{T}, s::Symbol) where {T,U} = Table{U}(t, Base.fieldindex(T, s))

Table(t::Table{T}, i::Integer) where {T} = Table{concretefieldtype(t,i)}(t, i)
Table(t::Table{T}, s::Symbol) where {T} = Table{concretefieldtype(t,s)}(t, s)

# TODO these are giving us bad VTables!
function tables(::Type{U}, t::Table{T}, i::Integer) where {U,T}
    s = fielddatastart(t, i)
    n = readval(Int32, t, s)
    s += 4
    # NOTE: that these element types are not concrete
    v = Vector{Table{U}}(undef, n)
    for i ∈ 1:n
        m = readval(Int32, t, s)
        v[i] = Table{U}(buffer(t), s+m)
        s += 4
    end
    v
end

default(t::Table{T}, i::Integer) where {T} = default(T, i)

nbytes(t::Table) = VTable(t).table_nbytes

tablestart(t::Table) = getfield(t, :start)
tableend(t::Table) = tablestart(t) + nbytes(t) - 1

Base.view(t::Table) = view(buffer(t), tablestart(t):tableend(t))

isdefault(t::Table, i::Integer) = i > length(VTable(t)) || iszero(VTable(t)[i])

fieldstart(t::Table, i::Integer) = tablestart(t) + VTable(t)[i]

function fieldend(t::Table{T}, i::Integer) where {T}
    U = fieldtype(T, i)
    # Int32 is default offset used for all references (I think)
    s = U <: BitsType ? sizeof(U) : sizeof(Int32)
    tablestart(t) + VTable(t)[i] + s - 1
end

function fielddatastart(t::Table, i::Integer)
    fs = fieldstart(t, i)
    fs + reinterpret(Int32, @view buffer(t)[fs:fieldend(t, i)])[1]
end

function bitsfield_nodefaultcheck(::Type{U}, t::Table{T}, i::Integer) where {T,U}
    reinterpret(U, @view buffer(t)[fieldstart(t, i):(fieldstart(t,i)+sizeof(U)-1)])[1]
end

function bitsfield(::Type{U}, t::Table{T}, i::Integer) where {U,T}
    isdefault(t, i) && return default(t, i)
    bitsfield_nodefaultcheck(U, t, i)
end

pointerfield(t::Table, i::Integer) = bitsfield(Int32, t, i)

uniontypefield(t::Table, i::Integer) = bitsfield(UInt8, t, i)

enumfield(::Type{T}, t::Table, i::Integer) where {U,T<:Enum{U}} = T(bitsfield(U, t, i))

function bitsvectorfield(::Type{<:AbstractVector{U}}, t::Table, i::Integer) where {U}
    isdefault(t, i) && return default(t, i)
    s = fielddatastart(t, i)
    n = reinterpret(Int32, @view buffer(t)[s:(s+3)])[1]
    Vector(reinterpret(U, @view buffer(t)[(s+4):(s+3 + n*sizeof(U))]))
end

# TODO this has not been tested at all
# , certainly not overly confident in this
function structvectorfield(::Type{<:AbstractVector{T}}, t::Table, i::Integer) where {T}
    isdefault(t, i) && return default(t, i)
    s = fielddatastart(t, i)
    n = reinterpret(Int32, @view buffer(t)[s:(s+3)])[1]
    s += 4
    v = Vector{T}(undef, n)
    for i ∈ 1:n
        v[i] = readstruct(T, buffer(t), s)
        s += nbytes(T)
    end
    v
end

function tablevectorfield(::Type{<:AbstractVector{T}}, t::Table, i::Integer) where {T}
    [t() for t ∈ tables(T, t, i)]
end

structfield(::Type{U}, t::Table, i::Integer) where {U} = readstruct(U, buffer(t), fieldstart(t, i))

# TODO will this break for unicode strings?  hopefully they are using nbytes
stringfield(t::Table, i::Integer) = String(bitsvectorfield(Vector{UInt8}, t, i))

function concretefieldtype(t::Table{T}, i::Integer) where {T}
    U = fieldtype(T, i)
    if BufferType(U) ≡ UnionType()
        uniontype(U, uniontypefield(t, i-1)+1)
    else
        U
    end
end
concretefieldtype(t::Table{T}, s::Symbol) where {T} = concretefieldtype(t, Base.fieldindex(T, s))

function field(::Type{U}, t::Table{T}, i::Integer) where {U,T}
    # NOTE: ordering here is not an accident, expensive and "less common" checks come later
    if U <: BitsType
        bitsfield(U, t, i)
    elseif U <: Enum
        enumfield(U, t, i)
    elseif U <: AbstractVector{<:BitsType}
        bitsvectorfield(U, t, i)
    elseif U <: AbstractString
        stringfield(t, i)
    elseif BufferType(U) ≡ StructType()
        structfield(U, t, i)
    elseif BufferType(U) ≡ TableType()
        Table{U}(t, i)()
    elseif elbuffertype(U) ≡ StructType()
        structvectorfield(U, t, i)
    elseif elbuffertype(U) ≡ TableType()
        tablevectorfield(U, t, i)
    else
        throw(ErrorException("what the fuck is this type?"))
    end
end
field(t::Table{T}, i::Integer) where {T} = field(concretefieldtype(t, i), t, i)

field(t::Table{T}, s::Symbol) where {T} = field(t, Base.fieldindex(T, s))

# NOTE: need both methods to resolve type ambiguity
Base.getproperty(t::Table, i::Integer) = field(t, i)
Base.getproperty(t::Table, s::Symbol) = field(t, s)
Base.propertynames(t::Table{T}) where {T} = fieldnames(T)

# TODO this constructor is definitely really horribly slow
(t::Table{T})() where {T} = T((field(t, i) for i ∈ 1:length(fieldtypes(T)))...)

