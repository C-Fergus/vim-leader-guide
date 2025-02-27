let s:save_cpo = &cpo
set cpo&vim

function! leaderGuide#has_configuration() "{{{
  return exists('s:desc_lookup')
endfunction "}}}
function! leaderGuide#register_prefix_descriptions(key, dictname) " {{{
  let key = a:key ==? '<Space>' ? ' ' : a:key
  if !exists('s:desc_lookup')
    call s:create_cache()
  endif
  if strlen(key) == 0
    let s:desc_lookup['top'] = a:dictname
    return
  endif
  if !has_key(s:desc_lookup, key)
    let s:desc_lookup[key] = a:dictname
  endif
endfunction "}}}
function! s:create_cache() " {{{
  let s:desc_lookup = {}
  let s:cached_dicts = {}
endfunction " }}}
function! s:create_target_dict(key) " {{{
  if has_key(s:desc_lookup, 'top')
    let toplevel = deepcopy({s:desc_lookup['top']})
    let tardict = s:toplevel ? toplevel : get(toplevel, a:key, {})
    let mapdict = s:cached_dicts[a:key]
    call s:merge(tardict, mapdict)
  elseif has_key(s:desc_lookup, a:key)
    let tardict = deepcopy({s:desc_lookup[a:key]})
    let mapdict = s:cached_dicts[a:key]
    call s:merge(tardict, mapdict)
  else
    let tardict = s:cached_dicts[a:key]
  endif
  return tardict
endfunction " }}}
function! s:merge(dict_t, dict_o) " {{{
  let target = a:dict_t
  let other = a:dict_o
  for k in keys(target)
    if (k ==? '<TAB>' || k ==? '<C-I>') && !(k ==# '<C-I>') 
      let target['<C-I>'] = target[k]
      unlet target[k]
      let k = '<C-I>'
    endif
    if type(target[k]) == type({}) && has_key(other, k)
      if type(other[k]) == type({})
        if has_key(target[k], 'name')
          let other[k].name = target[k].name
        endif
        call s:merge(target[k], other[k])
      elseif type(other[k]) == type([])
        if g:leaderGuide_flatten == 0 || type(target[k]) == type({})
          let target[k.'m'] = target[k]
        endif
        let target[k] = other[k]
        if has_key(other, k."m") && type(other[k."m"]) == type({})
          call s:merge(target[k."m"], other[k."m"])
        endif
      endif
    elseif type(target[k]) == type("") && has_key(other, k) && k != 'name'
      let target[k] = [other[k][0], target[k]]
    elseif g:leaderGuide_mode_local_only
      unlet target[k]
    endif
  endfor
  call extend(target, other, "keep")
endfunction " }}}

function! leaderGuide#populate_dictionary(key, dictname) " {{{
  call s:start_parser(a:key, s:cached_dicts[a:key])
endfunction " }}}
function! leaderGuide#parse_mappings() " {{{
  for [k, v] in items(s:cached_dicts)
    call s:start_parser(k, v)
  endfor
endfunction " }}}

function! s:start_parser(key, dict) " {{{
  let key = a:key ==? ' ' ? "<Space>" : a:key
  let readmap = ""
  redir => readmap
  silent execute 'map '.key
  redir END
  let lines = split(readmap, "\n")
  let visual = s:vis == "gv" ? 1 : 0

  for line in lines
    let mapd = maparg(split(line[3:])[0], line[0], 0, 1)
    if mapd.lhs =~ '<Plug>.*' || mapd.lhs =~ '<SNR>.*'
      continue
    endif
    let mapd.display = s:format_displaystring(mapd.rhs)
    let mapd.lhs = substitute(mapd.lhs, key, "", "")
    let mapd.lhs = substitute(mapd.lhs, "<Space>", " ", "g")
    let mapd.lhs = substitute(mapd.lhs, "<Tab>", "<C-I>", "g")
    let mapd.rhs = substitute(mapd.rhs, "<SID>", "<SNR>".mapd['sid']."_", "g")
    if mapd.lhs != '' && mapd.display !~# 'LeaderGuide.*'
      if (visual && match(mapd.mode, "[vx ]") >= 0) ||
            \ (!visual && match(mapd.mode, "[vx]") == -1)
        let mapd.lhs = s:string_to_keys(mapd.lhs)
        call s:add_map_to_dict(mapd, 0, a:dict)
      endif
    endif
  endfor
endfunction " }}}

function! s:add_map_to_dict(map, level, dict) " {{{
  if len(a:map.lhs) > a:level+1
    let curkey = a:map.lhs[a:level]
    let nlevel = a:level+1
    if !has_key(a:dict, curkey)
      let a:dict[curkey] = { 'name' : g:leaderGuide_default_group_name }
      " mapping defined already, flatten this map
    elseif type(a:dict[curkey]) == type([]) && g:leaderGuide_flatten
      let cmd = s:escape_mappings(a:map)
      let curkey = join(a:map.lhs[a:level+0:], '')
      let nlevel = a:level
      if !has_key(a:dict, curkey)
        let a:dict[curkey] = [cmd, a:map.display]
      endif
    elseif type(a:dict[curkey]) == type([]) && g:leaderGuide_flatten == 0
      let cmd = s:escape_mappings(a:map)
      let curkey = curkey."m"
      if !has_key(a:dict, curkey)
        let a:dict[curkey] = { 'name' : g:leaderGuide_default_group_name }
      endif
    endif
    " next level
    if type(a:dict[curkey]) == type({})
      call s:add_map_to_dict(a:map, nlevel, a:dict[curkey])
    endif
  else
    let cmd = s:escape_mappings(a:map)
    if !has_key(a:dict, a:map.lhs[a:level])
      let a:dict[a:map.lhs[a:level]] = [cmd, a:map.display]
      " spot is taken already, flatten existing submaps
    elseif type(a:dict[a:map.lhs[a:level]]) == type({}) && g:leaderGuide_flatten
      let childmap = s:flattenmap(a:dict[a:map.lhs[a:level]], a:map.lhs[a:level])
      for it in keys(childmap)
        let a:dict[it] = childmap[it]
      endfor
      let a:dict[a:map.lhs[a:level]] = [cmd, a:map.display]
    endif
  endif
endfunction " }}}
function! s:format_displaystring(map) " {{{
  let g:leaderGuide#displayname = a:map
  for Fun in g:leaderGuide_displayfunc
    call Fun()
  endfor
  let display = g:leaderGuide#displayname
  unlet g:leaderGuide#displayname
  return display
endfunction " }}}
function! s:flattenmap(dict, str) " {{{
  let ret = {}
  for kv in keys(a:dict)
    if type(a:dict[kv]) == type([])
      return {a:str.kv : a:dict[kv]}
    elseif type(a:dict[kv]) == type({})
      let strcall = a:str.kv
      call extend(ret, s:flattenmap(a:dict[kv], a:str.kv))
    endif
  endfor
  return ret
endfunction " }}}


function! s:escape_mappings(mapping) " {{{
  let feedkeyargs = a:mapping.noremap ? "nt" : "mt"
  let rstring = substitute(a:mapping.rhs, '\', '\\\\', 'g')
  let rstring = substitute(rstring, '<\([^<>]*\)>', '\\<\1>', 'g')
  let rstring = substitute(rstring, '"', '\\"', 'g')
  let rstring = 'call feedkeys("'.rstring.'", "'.feedkeyargs.'")'
  return rstring
endfunction " }}}
function! s:string_to_keys(input) " {{{
  " Avoid special case: <>
  if match(a:input, '<.\+>') != -1
    let retlist = []
    let si = 0
    let go = 1
    while si < len(a:input)
      if go
        call add(retlist, a:input[si])
      else
        let retlist[-1] .= a:input[si]
      endif
      if a:input[si] ==? '<'
        let go = 0
      elseif a:input[si] ==? '>'
        let go = 1
      end
      let si += 1
    endw
    return retlist
  else
    return split(a:input, '\zs')
  endif
endfunction " }}}
function! s:escape_keys(inp) " {{{
  let ret = substitute(a:inp, "<", "<lt>", "")
  return substitute(ret, "|", "<Bar>", "")
endfunction " }}}
" displaynames {{{
let s:custom_key_name_map_check = 0
let s:displaynames = {'<C-I>': '<Tab>', '<C-H>': '<BS>', ' ': 'SPC'}
" }}}
function! s:show_displayname(inp) " {{{
  if !s:custom_key_name_map_check " only call on first run
    if exists('g:leaderGuide_key_name_map')
      call extend(s:displaynames, g:leaderGuide_key_name_map, 'force')
    endif
    let s:custom_key_name_map_check = 1
  endif
  if (a:inp ==? '<c-i>' || a:inp ==? '<c-h>')
    call toupper(a:inp)
  endif
  return get(s:displaynames, a:inp, a:inp)
endfunction " }}}

function! s:calc_layout() " {{{
  let ret = {}
  let smap = filter(copy(s:lmap), '(v:key !=# "name") && !(type(v:val) == type([]) && v:val[1] == "leader_ignore")')
  let ret.n_items = len(smap)
  let length = values(map(smap, 
        \ 'strdisplaywidth("[".s:show_displayname(v:key)."]".'.
        \ '(type(v:val) == type({}) ?'.
        \ '(g:leaderGuide_display_plus_menus ? "+".v:val["name"] : v:val["name"])'.
        \ ': v:val[1]))'))
  let maxlength = max(length) + g:leaderGuide_hspace
  if g:leaderGuide_vertical
    let ret.n_rows = winheight(0) - 2
    let ret.n_cols = ret.n_items / ret.n_rows + (ret.n_items != ret.n_rows)
    let ret.col_width = maxlength
    let ret.win_dim = ret.n_cols * ret.col_width
  else
    let ret.n_cols = winwidth(0) / maxlength
    let ret.col_width = winwidth(0) / ret.n_cols
    let ret.n_rows = ret.n_items / ret.n_cols + (fmod(ret.n_items,ret.n_cols) > 0 ? 1 : 0)
    let ret.win_dim = ret.n_rows + ((g:leaderGuide_position[:2] ==? 'top') ? 0 : &cmdheight - 1)
  endif
  let ret.win_dim = g:leaderGuide_max_size ? min([g:leaderGuide_max_size, ret.win_dim]) : ret.win_dim
  return ret
endfunction " }}}

function! s:create_string(layout) " {{{
  let l = a:layout
  let l.capacity = l.n_rows * l.n_cols
  let overcap = l.capacity - l.n_items
  let overh = l.n_cols - overcap
  let n_rows =  l.n_rows - 1
  let rows = []
  let row = 0
  let col = 0
  let smap = sort(filter(keys(s:lmap), 'v:val !=# "name"'),'1')
  for k in smap
    silent execute "cnoremap <nowait> <buffer> ".substitute(k, "|", "<Bar>", ""). " " . s:escape_keys(k) ."<CR>"
    let desc = type(s:lmap[k]) == type({}) ? s:lmap[k].name : s:lmap[k][1]
    if desc !=? "leader_ignore"
      let displaystring = "[".s:show_displayname(k)."] ".(g:leaderGuide_display_plus_menus ? (type(s:lmap[k]) == type({}) ? "+" : "") : "").desc
      let crow = get(rows, row, [])
      if empty(crow)
        call add(rows, crow)
      endif
      call add(crow, displaystring)
      call add(crow, repeat(' ', l.col_width - strdisplaywidth(displaystring)))
      if !g:leaderGuide_sort_horizontal
        if row >= n_rows - 1
          if overh > 0 && row < n_rows
            let overh -= 1
            let row += 1
          else
            let row = 0
            let col += 1
          endif
        else
          let row += 1
        endif
      else
        if col == l.n_cols - 1
          let row +=1
          let col = 0
        else
          let col += 1
        endif
      endif
    endif
  endfor
  cnoremap <nowait> <buffer> <Space> <Space><CR>
  cnoremap <nowait> <buffer> <silent> <c-c> <LGCMD>submode<CR>
  return map(rows, 'join(v:val, "")')
endfunction " }}}

function! s:start_buffer() " {{{
  call s:winopen()
  let l:string_arr = s:create_string(s:layout)
  let l:start = 0
  if g:leaderGuide_vertical && (g:leaderGuide_position[:2] ==? 'bot')
    call nvim_buf_set_lines(s:bufnr, 0, -1, 0, repeat([''], winheight(0) + 1 - &cmdheight))
    let l:start = -len(l:string_arr)-1
  endif
  call nvim_buf_set_lines(s:bufnr, l:start, -1, 0, l:string_arr)
  call s:wait_for_input()
endfunction " }}}

function! s:handle_input(input) " {{{
  call s:winclose()
  if type(a:input) ==? type({})
    let s:lmap = a:input
    call s:start_buffer()
  else
    if (type(a:input) != type(0)) " key not in dict
      try
        unsilent execute a:input[0]
      catch
        unsilent echom v:exception
      endtry
    endif
  endif
endfunction " }}}

function! s:wait_for_input() " {{{
  redraw
  let inp = input('')
  if inp ==? ''
    call s:winclose()
  elseif match(inp, "^<LGCMD>submode") == 0
    call s:submode_mappings()
  else
    if g:leaderGuide_match_whole == 1
      let fsel = get(s:lmap, inp)
    elseif inp[-5:] ==? '<C-I>' || inp[-5:] ==? '<TAB>'
      let fsel = get(s:lmap, inp[-5:])
    else
      let fsel = get(s:lmap, inp[-1:])
    endif
    call s:handle_input(fsel)
  endif
endfunction " }}}

function! s:winopen() " {{{

  let vert = g:leaderGuide_vertical

  if exists('*popup_create')

    let a:position = g:leaderGuide_position
    let s:bufnr = bufadd('Leader-Guide')

    let guidewinid = popup_create(s:bufnr, {
    \ 'pos': a:position,
    \ 'border': [],
    \ 'borderchars': ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
    \ 'padding': [0,1,0,1],
    \ })

  else

    let left = (g:leaderGuide_position[3:] ==? 'left')
    let top = (g:leaderGuide_position[:2] ==? 'top')
    let s:bufnr = nvim_create_buf(v:false, v:false)

    call nvim_open_win(s:bufnr, v:true, {
          \'relative' : 'editor',
          \'style' : 'minimal',
          \'anchor' : (vert ? (left ? 'NW' : 'NE') : (top ? 'NW' : 'SW')), 
          \'row' : ((!vert && !top) ? &lines : 0),
          \'col' : ((vert && !left) ? &columns : 0), 
          \'width': &columns,
          \'height' : &lines
          \})

  endif

  let s:gwin = winnr()
  let s:layout = s:calc_layout()
  noautocmd execute (g:leaderGuide_vertical ? 'vert res ' : 'res ') s:layout.win_dim
  setlocal filetype=leaderGuide nobuflisted buftype=nofile bufhidden=unload noswapfile
  setlocal winfixwidth winfixheight
  if has('nvim')
    setlocal winhighlight=Normal:LeaderGuideFloating
  endif

endfunction " }}}

"function! s:winopen() " {{{
"  let s:bufnr = nvim_create_buf(v:false, v:false)
"  let vert = g:leaderGuide_vertical
"  let left = (g:leaderGuide_position[3:] ==? 'left')
"  let top = (g:leaderGuide_position[:2] ==? 'top')
"  call nvim_open_win(s:bufnr, v:true, {'relative' : 'editor', 'style' : 'minimal',
"        \'anchor' : (vert ? (left ? 'NW' : 'NE') : (top ? 'NW' : 'SW')), 
"        \'row' : ((!vert && !top) ? &lines : 0), 'col' : ((vert && !left) ? &columns : 0), 
"        \'width': &columns, 'height' : &lines})
"  let s:gwin = winnr()
"  let s:layout = s:calc_layout()
"  noautocmd execute (g:leaderGuide_vertical ? 'vert res ' : 'res ') s:layout.win_dim
"  setlocal filetype=leaderGuide nobuflisted buftype=nofile bufhidden=unload noswapfile
"  setlocal winfixwidth winfixheight winhighlight=Normal:LeaderGuideFloating
"endfunction " }}}

function! s:winclose() " {{{
  if s:gwin == winnr()
    close!
  endif
endfunction " }}}

function! s:page_down() " {{{
  call feedkeys("\<c-c>", "n")
  call feedkeys("\<c-f>", "x")
  call s:wait_for_input()
endfunction " }}}
function! s:page_up() " {{{
  call feedkeys("\<c-c>", "n")
  call feedkeys("\<c-b>", "x")
  call s:wait_for_input()
endfunction " }}}

function! s:handle_submode_mapping(cmd) " {{{
  if a:cmd ==? '<LGCMD>page_down'
    call s:page_down()
  elseif a:cmd ==? '<LGCMD>page_up'
    call s:page_up()
  elseif a:cmd ==? '<LGCMD>win_close'
    call s:winclose()
  endif
endfunction " }}}
function! s:submode_mappings() " {{{
  let submodestring = ""
  let maplist = []
  for key in items(g:leaderGuide_submode_mappings)
    let map = maparg(key[0], "c", 0, 1)
    if !empty(map)
      call add(maplist, map)
    endif
    execute 'cnoremap <nowait> <silent> <buffer> '.key[0].' <LGCMD>'.key[1].'<CR>'
    let submodestring = submodestring.' '.key[0].': '.key[1].','
  endfor
  let inp = input(strpart(submodestring, 0, strlen(submodestring)-1))
  for map in maplist
    call s:mapmaparg(map)
  endfor
  silent call s:handle_submode_mapping(inp)
endfunction " }}}
function! s:mapmaparg(maparg) " {{{
  let noremap = a:maparg.noremap ? 'noremap' : 'map'
  let buffer = a:maparg.buffer ? '<buffer> ' : ''
  let silent = a:maparg.silent ? '<silent> ' : ''
  let nowait = a:maparg.nowait ? '<nowait> ' : ''
  let st = a:maparg.mode.''.noremap.' '.nowait.silent.buffer.''.a:maparg.lhs.' '.a:maparg.rhs
  execute st
endfunction " }}}

function! leaderGuide#start_by_prefix(vis, key) " {{{
  let s:vis = a:vis ? 'gv' : ''
  let s:count = v:count != 0 ? v:count : ''
  let s:toplevel = a:key ==? '  '
  if has('nvim') && !exists('s:reg')
    let s:reg = ''
  else
    let s:reg = v:register != s:get_register() ? '"'.v:register : ''
  endif
  if !has_key(s:cached_dicts, a:key) || g:leaderGuide_run_map_on_popup
    "first run
    let s:cached_dicts[a:key] = {}
    call s:start_parser(a:key, s:cached_dicts[a:key])
  endif    
  if has_key(s:desc_lookup, a:key) || has_key(s:desc_lookup , 'top')
    let rundict = s:create_target_dict(a:key)
  else
    let rundict = s:cached_dicts[a:key]
  endif
  let s:lmap = rundict
  call s:start_buffer()
endfunction " }}}
function! leaderGuide#start(vis, dict) " {{{
  let s:vis = a:vis ? 'gv' : 0
  let s:count = v:count != 0 ? v:count : ''
  if has('nvim') && !exists('s:reg')
    let s:reg = ''
  else
    let s:reg = v:register != s:get_register() ? '"'.v:register : ''
  endif
  let s:lmap = a:dict
  call s:start_buffer()
endfunction " }}}

function! s:get_register() " {{{
  if match(&clipboard, 'unnamedplus') >= 0
    let clip = '+'
  elseif match(&clipboard, 'unnamed') >= 0
    let clip = '*'
  else
    let clip = '"'
  endif
  return clip
endfunction " }}}

let &cpo = s:save_cpo
unlet s:save_cpo
