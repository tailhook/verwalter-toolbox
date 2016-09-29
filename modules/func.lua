local function map(func, array)
  local new_array = {}
  for i,v in ipairs(array) do
    new_array[i] = func(v)
  end
  return new_array
end

local function map_pairs(func, array)
  local new_array = {}
  for k,v in pairs(array) do
    new_array[k] = func(k, v)
  end
  return new_array
end

local function map_to_dict(func, array)
  local new_array = {}
  for k,v in pairs(array) do
    local nk, nv = func(k, v)
    new_array[nk] = nv
  end
  return new_array
end

local function map_to_array(func, array)
  local new_array = {}
  for k,v in pairs(array) do
    local nv = func(k, v)
    new_array[#new_array+1] = nv
  end
  return new_array
end

local function map_reverse(func, array)
  local new_array = {}
  for i=#array,1,-1 do
    new_array[#new_array+1] = func(array[i])
  end
  return new_array
end

local function filter(func, array)
  local new_array = {}
  for _, v in pairs(array) do
    if func(v) then
        new_array[#new_array+1] = v
    end
  end
  return new_array
end

local function filter_pairs(func, dict)
  local items = {}
  for k, v in pairs(dict) do
    local nk, nv = func(k, v)
    if nk ~= nil then
        items[nk] = nv
    end
  end
  return items
end

local function count_keys(dict)
    local res = 0
    for _, _ in pairs(dict) do
        res = res + 1
    end
    return res
end

local function _copy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = deepcopy(orig_value)
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local function contains(haystack, needle)
    for _, x in pairs(haystack) do
        if x == needle then
            return true
        end
    end
    return false
end

local function sorted(src)
    local dest = _copy(src)
    table.sort(dest)
    return dest
end

local function range_step_num(start, step, num)
    local result = {}
    for i=start,start+step*(num-1),step do
        result[#result+1] = i
    end
    return result
end

local function repeat_num(value, num)
    local result = {}
    for i=1,num do
        result[i] = value
    end
    return result
end

local function list_to_set(list)
    local res = {}
    for _, val in pairs(list) do
        res[val] = true
    end
    return res
end

local function merge_tables(...)
    local result = {}
    for _, dic in ipairs({...}) do
        for k, v in pairs(dic) do
            result[k] = v
        end
    end
    return result
end

local function sum(table)
    local result = 0
    for _, v in pairs(table) do
        result = result + v
    end
    return result
end

return {
    map=map,
    map_pairs=map_pairs,
    map_reverse=map_reverse,
    map_to_dict=map_to_dict,
    map_to_array=map_to_array,
    filter=filter,
    filter_pairs=filter_pairs,
    count_keys=count_keys,
    copy=_copy,
    deepcopy=deepcopy,
    contains=contains,
    sorted=sorted,
    range_step_num=range_step_num,
    repeat_num=repeat_num,
    list_to_set=list_to_set,
    merge_tables=merge_tables,
    sum=sum,
}
