--------------------------------------------------------------------------------
-- oan_file_pkg (FR-33): validated storage + single authorized download path
--------------------------------------------------------------------------------
create or replace package oan_file_pkg authid definer as
  -- p_temp_name: value of a File Browse item (APEX_APPLICATION_TEMP_FILES.NAME)
  function store(p_temp_name in varchar2, p_object_type in varchar2) return number;
  function store_blob(p_blob in blob, p_filename in varchar2, p_mime in varchar2,
                      p_object_type in varchar2, p_owner_id in number) return number;
  -- Authorization + payload for the native Download process (attachment, nosniff headers set by app)
  procedure get_file(p_file_id in number, p_blob out blob, p_filename out varchar2, p_mime out varchar2);
  function can_download(p_file_id in number) return boolean;
  function can_download_yn(p_file_id in number) return varchar2;   -- SQL-callable, used by OAN_DOWNLOAD_V
  procedure link_object(p_file_id in number, p_object_id in number);
end oan_file_pkg;
/

create or replace package body oan_file_pkg as
  c_max_size  constant number := 20 * 1024 * 1024;

  function ext_of(p_name in varchar2) return varchar2 is
  begin
    return lower(regexp_substr(p_name, '\.([[:alnum:]]+)$', 1, 1, null, 1));
  end ext_of;

  procedure validate(p_blob in blob, p_filename in varchar2, p_object_type in varchar2) is
    l_ext   varchar2(10) := ext_of(p_filename);
    l_magic raw(8)       := dbms_lob.substr(p_blob, 8, 1);
    l_ok    boolean;
  begin
    oan_util.assert(dbms_lob.getlength(p_blob) between 1 and c_max_size, 'Files must be 20 MB or smaller.');
    if p_object_type = 'PROFILE_PHOTO' then
      oan_util.assert(l_ext in ('png','jpg','jpeg'), 'Profile photos must be PNG or JPG.');
    elsif p_object_type = 'CV' then
      oan_util.assert(l_ext in ('pdf','docx'), 'Your CV must be a PDF or Word (.docx) file.');
    else
      oan_util.assert(l_ext in ('pdf','docx','pptx','xlsx','png','jpg','jpeg'),
                      'Allowed file types: pdf, docx, pptx, xlsx, png, jpg.');
    end if;
    -- Extension and magic bytes must agree (FR-33)
    l_ok := case
              when l_ext = 'pdf'                      then utl_raw.substr(l_magic, 1, 4) = hextoraw('25504446')
              when l_ext in ('docx','pptx','xlsx')    then utl_raw.substr(l_magic, 1, 4) = hextoraw('504B0304')
              when l_ext = 'png'                      then utl_raw.substr(l_magic, 1, 8) = hextoraw('89504E470D0A1A0A')
              when l_ext in ('jpg','jpeg')            then utl_raw.substr(l_magic, 1, 3) = hextoraw('FFD8FF')
              else false
            end;
    oan_util.assert(l_ok, 'The file content does not match its extension.');
  end validate;

  function mime_of(p_ext in varchar2) return varchar2 is
  begin
    return case p_ext
             when 'pdf'  then 'application/pdf'
             when 'docx' then 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
             when 'pptx' then 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
             when 'xlsx' then 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
             when 'png'  then 'image/png'
             when 'zip'  then 'application/zip'
             when 'csv'  then 'text/csv'
             else 'image/jpeg'
           end;
  end mime_of;

  function store_blob(p_blob in blob, p_filename in varchar2, p_mime in varchar2,
                      p_object_type in varchar2, p_owner_id in number) return number is
    l_id    number;
    l_quota number;
    l_mime  varchar2(200);
  begin
    if p_object_type in ('PROFILE_PHOTO','LIBRARY_ITEM','CV') then
      validate(p_blob, p_filename, p_object_type);
      select coalesce(sum(file_size), 0) into l_quota from oan_files
       where owner_id = p_owner_id and object_type in ('PROFILE_PHOTO','LIBRARY_ITEM','CV');
      oan_util.assert(l_quota + dbms_lob.getlength(p_blob)
                        <= oan_util.get_config_num('UPLOAD_QUOTA_MB', 500) * 1024 * 1024,
                      'Upload quota reached (500 MB).');
    end if;
    l_mime := coalesce(p_mime, mime_of(ext_of(p_filename)));
    insert into oan_files (owner_id, filename, mime_type, file_size, sha256, content, object_type)
    values (p_owner_id, substr(regexp_replace(p_filename, '[^[:alnum:]._ -]', '_'), 1, 400),
            l_mime, dbms_lob.getlength(p_blob),
            dbms_crypto.hash(p_blob, dbms_crypto.hash_sh256), p_blob, p_object_type)
    returning id into l_id;
    return l_id;
  end store_blob;

  function store(p_temp_name in varchar2, p_object_type in varchar2) return number is
    l_blob blob;
    l_name varchar2(400);
    l_id   number;
  begin
    oan_util.assert(oan_util.viewer_id is not null, 'Not signed in.', oan_util.c_err_forbidden);
    select blob_content, filename into l_blob, l_name
      from apex_application_temp_files where name = p_temp_name;
    -- MIME is derived from the validated extension, never trusted from the browser
    l_id := store_blob(l_blob, l_name, mime_of(ext_of(l_name)), p_object_type, oan_util.viewer_id);
    delete from apex_application_temp_files where name = p_temp_name;
    return l_id;
  exception
    when no_data_found then
      oan_util.raise_error(oan_util.c_err_validation, 'Upload not found. Please choose the file again.');
  end store;

  procedure link_object(p_file_id in number, p_object_id in number) is
  begin
    update oan_files set object_id = p_object_id where id = p_file_id and owner_id = oan_util.viewer_id;
  end link_object;

  function can_download(p_file_id in number) return boolean is
    l_file oan_files%rowtype;
    l_cnt  number;
  begin
    select * into l_file from oan_files where id = p_file_id;
    case l_file.object_type
      when 'PROFILE_PHOTO' then
        select count(*) into l_cnt from oan_profiles p
         where p.photo_file_id = p_file_id and oan_vis.can_see_ref(p.user_id, 'PHOTO') = 'Y';
        return l_cnt > 0;
      when 'LIBRARY_ITEM' then
        -- visible published item, or the author, or a moderator reviewing it
        select count(*) into l_cnt from oan_library_v v where v.file_id = p_file_id;
        if l_cnt > 0 then return true; end if;
        return l_file.owner_id = oan_util.viewer_id or oan_security_pkg.is_moderator;
      when 'PRIVACY_EXPORT' then
        -- owner only, recently re-authenticated, before expiry (FR-26 AC1)
        select count(*) into l_cnt from oan_privacy_requests r
         where r.file_id = p_file_id and r.user_id = oan_util.viewer_id and r.file_expires_at > systimestamp;
        return l_cnt > 0 and oan_auth_pkg.is_recently_reauthenticated(15);
      when 'IMPORT_BATCH' then
        return oan_security_pkg.is_admin;
      when 'CV' then
        -- CV section is PRIVATE (R13): owner only until per-application shares (W2.7)
        return l_file.owner_id = oan_util.viewer_id;
      else
        return false;
    end case;
  exception
    when no_data_found then return false;
  end can_download;

  function can_download_yn(p_file_id in number) return varchar2 is
  begin
    return case when can_download(p_file_id) then 'Y' else 'N' end;
  end can_download_yn;

  procedure get_file(p_file_id in number, p_blob out blob, p_filename out varchar2, p_mime out varchar2) is
  begin
    if not can_download(p_file_id) then
      oan_audit_pkg.log_autonomous('DOWNLOAD_DENIED', 'FILE', p_file_id);
      oan_util.raise_error(oan_util.c_err_forbidden, 'You do not have access to this file.');
    end if;
    select content, filename, mime_type into p_blob, p_filename, p_mime from oan_files where id = p_file_id;
  end get_file;

end oan_file_pkg;
/
