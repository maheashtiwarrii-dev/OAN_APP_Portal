--------------------------------------------------------------------------------
-- oan_library_pkg (FR-19 incl. P21 IP/confidentiality controls, FR-08 P1)
--------------------------------------------------------------------------------
create or replace package oan_library_pkg authid definer as
  function submit(p_title in varchar2, p_summary in varchar2, p_item_type in varchar2,
                  p_url in varchar2, p_file_id in number, p_category in varchar2,
                  p_owner_type in varchar2, p_rights_basis in varchar2, p_rights_note in varchar2,
                  p_attested in varchar2, p_tag_ids in varchar2,
                  p_skill_level in varchar2 default null, p_provider in varchar2 default null,
                  p_duration_minutes in number default null, p_delivery_format in varchar2 default null,
                  p_chapter_ids in varchar2 default null) return number;
  procedure screen(p_item_id in number);
  procedure review(p_item_id in number, p_decision in varchar2, p_reason in varchar2);
  procedure set_featured(p_item_id in number, p_featured in varchar2);
  procedure record_view(p_item_id in number);
  procedure toggle_helpful(p_item_id in number);
  function  report_ip(p_item_id in number, p_reason in varchar2, p_details in varchar2,
                      p_email in varchar2) return number;                       -- public (no login)
  procedure triage_ip(p_report_id in number, p_uphold in varchar2, p_note in varchar2);
  procedure auto_hide_overdue_ip;                                               -- job
  function  import_csv(p_file_id in number) return number;                      -- returns batch id
end oan_library_pkg;
/

create or replace package body oan_library_pkg as

  procedure set_tags(p_item_id in number, p_tag_ids in varchar2) is
  begin
    delete from oan_library_item_tags where item_id = p_item_id;
    insert into oan_library_item_tags (item_id, term_id)
    select distinct p_item_id, oan_taxonomy_pkg.canonical_of(t.id)
      from oan_taxonomy_terms t
     where t.id in (select column_value from table(apex_string.split_numbers(p_tag_ids, ':')))
       and t.status in ('APPROVED','MERGED');
  end set_tags;

  procedure set_scope(p_item_id in number, p_chapter_ids in varchar2) is
  begin
    delete from oan_scope_chapters where object_type = 'LIBRARY_ITEM' and object_id = p_item_id;
    insert into oan_scope_chapters (object_type, object_id, chapter_id)
    select 'LIBRARY_ITEM', p_item_id, column_value
      from table(apex_string.split_numbers(p_chapter_ids, ':'));
  end set_scope;

  procedure notify_followers(p_item_id in number) is
    l_title oan_library_items.title%type;
  begin
    select title into l_title from oan_library_items where id = p_item_id;
    for f in (select distinct tf.user_id
                from oan_library_item_tags t
                join oan_tag_follows tf on tf.term_id = t.term_id
                join oan_users u on u.id = tf.user_id and u.status = 'ACTIVE'
               where t.item_id = p_item_id) loop
      oan_notify_pkg.notify(f.user_id, 'LIBRARY_FOLLOWED_TAG', 'New in the Library: ' || l_title, null,
                            35, 'P35_ID:' || p_item_id, 'LIBRARY_ITEM', p_item_id);
    end loop;
  end notify_followers;

  procedure publish(p_item_id in number) is
  begin
    update oan_library_items set status = 'PUBLISHED', published_at = systimestamp,
                                 title = title, row_version = row_version + 1   -- title touch re-syncs Text index
     where id = p_item_id;
    notify_followers(p_item_id);
  end publish;

  procedure screen(p_item_id in number) is
    l_item  oan_library_items%rowtype;
    l_blob  blob;
    l_text  clob;
    l_hits  varchar2(1000);
  begin
    select * into l_item from oan_library_items where id = p_item_id for update;
    if l_item.file_id is not null then
      select content into l_blob from oan_files where id = l_item.file_id;
      begin
        dbms_lob.createtemporary(l_text, true);
        ctx_doc.policy_filter(policy_name => 'OAN_FILTER_POLICY', document => l_blob,
                              restab => l_text, plaintext => true);
      exception
        when others then l_text := null;   -- extraction unavailable: falls back to manual review
      end;
    end if;
    -- Confidentiality markers and customer names (FR-19 item 3)
    for d in (select term, term_type from oan_screen_denylist) loop
      if instr(upper(l_item.title || ' ' || l_item.summary), upper(d.term)) > 0
         or (l_text is not null and dbms_lob.instr(upper(l_text), upper(d.term)) > 0) then
        l_hits := substr(l_hits || case when l_hits is not null then '; ' end || d.term_type || ':' || d.term, 1, 1000);
      end if;
    end loop;
    if l_item.file_id is not null and l_text is null then
      l_hits := substr(coalesce(l_hits, 'TEXT_EXTRACTION_FAILED'), 1, 1000);
    end if;
    update oan_library_items
       set extracted_text = l_text,
           screening_status = case when l_hits is null then 'CLEAR' else 'FLAGGED' end,
           screening_hits = l_hits
     where id = p_item_id;
  end screen;

  function submit(p_title in varchar2, p_summary in varchar2, p_item_type in varchar2,
                  p_url in varchar2, p_file_id in number, p_category in varchar2,
                  p_owner_type in varchar2, p_rights_basis in varchar2, p_rights_note in varchar2,
                  p_attested in varchar2, p_tag_ids in varchar2,
                  p_skill_level in varchar2 default null, p_provider in varchar2 default null,
                  p_duration_minutes in number default null, p_delivery_format in varchar2 default null,
                  p_chapter_ids in varchar2 default null) return number is
    l_id number;
  begin
    oan_security_pkg.require_active_member;
    oan_util.assert(p_attested = 'Y',
      'Confirm that the item contains no Oracle-confidential, customer-confidential or third-party proprietary material.');
    oan_util.assert(p_rights_basis in ('OAN_OWNED','CONTRIBUTOR_OWNED','LICENSED','PUBLICLY_AVAILABLE'),
      'Choose the rights basis for this item.');
    oan_util.assert(p_rights_basis = 'OAN_OWNED' or oan_security_pkg.is_admin or p_owner_type != 'OAN',
      'Only administrators can mark content as OAN-owned.');
    oan_util.assert(p_url is null or regexp_like(p_url, '^https://', 'i'), 'Links must start with https://');

    insert into oan_library_items (title, summary, item_type, url, file_id, category, owner_type, author_id,
                                   rights_basis, rights_note, attested, attested_at, status,
                                   skill_level, provider, duration_minutes, delivery_format)
    values (p_title, p_summary, p_item_type, p_url, p_file_id, p_category, p_owner_type, oan_util.viewer_id,
            p_rights_basis, p_rights_note, 'Y', systimestamp, 'PENDING_REVIEW',
            p_skill_level, p_provider, p_duration_minutes, p_delivery_format)
    returning id into l_id;
    if p_file_id is not null then oan_file_pkg.link_object(p_file_id, l_id); end if;
    set_tags(l_id, p_tag_ids);
    if p_chapter_ids is not null then set_scope(l_id, p_chapter_ids); end if;
    screen(l_id);
    oan_audit_pkg.log('LIBRARY_SUBMIT', 'LIBRARY_ITEM', l_id);
    -- All non-import submissions are pre-moderated (Q12), including admin ones, so screening + second review apply
    oan_notify_pkg.notify_role('MODERATOR', 'MODERATION_QUEUE', 'Library item awaiting review', p_title, 107,
                               oan_util.viewer_id);
    return l_id;
  end submit;

  procedure review(p_item_id in number, p_decision in varchar2, p_reason in varchar2) is
    l_item oan_library_items%rowtype;
  begin
    oan_util.assert(oan_security_pkg.is_moderator, 'Not authorized.', oan_util.c_err_forbidden);
    select * into l_item from oan_library_items where id = p_item_id for update;
    oan_security_pkg.require_not_self(l_item.author_id);
    oan_util.assert(l_item.status in ('PENDING_REVIEW','PENDING_SECOND_REVIEW'), 'This item is not awaiting review.');

    if p_decision = 'REJECT' then
      oan_util.assert(p_reason is not null, 'Give a reason for the contributor.');
      update oan_library_items set status = 'REJECTED', row_version = row_version + 1 where id = p_item_id;
    elsif l_item.status = 'PENDING_SECOND_REVIEW' then
      oan_util.assert(oan_util.viewer_id != l_item.first_reviewer_id,
                      'The second review must be done by a different administrator.', oan_util.c_err_forbidden);
      oan_util.assert(oan_security_pkg.is_admin, 'The second review requires a Platform Admin.', oan_util.c_err_forbidden);
      update oan_library_items set second_reviewer_id = oan_util.viewer_id where id = p_item_id;
      publish(p_item_id);
    elsif l_item.category in ('SALES','PRODUCT') or l_item.screening_status = 'FLAGGED' then
      -- Sales/Product items and screening hits need a second, different admin (FR-19 item 2/3)
      update oan_library_items set status = 'PENDING_SECOND_REVIEW', first_reviewer_id = oan_util.viewer_id,
                                   row_version = row_version + 1
       where id = p_item_id;
    else
      update oan_library_items set first_reviewer_id = oan_util.viewer_id where id = p_item_id;
      publish(p_item_id);
    end if;

    insert into oan_moderation_actions (object_type, object_id, queue, action, reason, actor_id, subject_user_id)
    values ('LIBRARY_ITEM', p_item_id, 'PRE',
            case when p_decision = 'REJECT' then 'REJECT'
                 when l_item.status = 'PENDING_SECOND_REVIEW' then 'SECOND_APPROVE' else 'APPROVE' end,
            p_reason, oan_util.viewer_id, l_item.author_id);
    oan_audit_pkg.log('LIBRARY_REVIEW', 'LIBRARY_ITEM', p_item_id, l_item.author_id,
                      json_object('decision' value p_decision));
    if l_item.author_id is not null then
      oan_notify_pkg.notify(l_item.author_id, 'MODERATION_DECISION',
        'Your Library submission "' || l_item.title || '" was '
          || case p_decision when 'REJECT' then 'not accepted' else 'reviewed' end,
        p_reason, 81);
    end if;
  end review;

  procedure set_featured(p_item_id in number, p_featured in varchar2) is
  begin
    oan_security_pkg.require_admin;
    update oan_library_items set is_featured = p_featured where id = p_item_id and status = 'PUBLISHED';
  end set_featured;

  procedure record_view(p_item_id in number) is
  begin
    update oan_library_items set view_count = view_count + 1 where id = p_item_id and status = 'PUBLISHED';
  end record_view;

  procedure toggle_helpful(p_item_id in number) is
    l_cnt number;
  begin
    oan_security_pkg.require_active_member;
    delete from oan_library_votes where item_id = p_item_id and user_id = oan_util.viewer_id;
    if sql%rowcount = 0 then
      insert into oan_library_votes (item_id, user_id) values (p_item_id, oan_util.viewer_id);
    end if;
    select count(*) into l_cnt from oan_library_votes where item_id = p_item_id;
    update oan_library_items set helpful_count = l_cnt where id = p_item_id;
  end toggle_helpful;

  function report_ip(p_item_id in number, p_reason in varchar2, p_details in varchar2,
                     p_email in varchar2) return number is
    l_id number;
  begin
    oan_throttle_pkg.enforce('IPREPORT:IP:' || oan_util.client_ip, 5, 1440);
    insert into oan_ip_reports (item_id, reporter_user_id, reporter_email, reporter_ip_hash, reason, details, hide_due_at)
    values (p_item_id, oan_util.viewer_id, lower(p_email), oan_util.sha256(oan_util.client_ip), p_reason,
            substr(p_details, 1, 4000), oan_util.add_business_days(systimestamp, 1))
    returning id into l_id;
    oan_audit_pkg.log('IP_REPORT', 'LIBRARY_ITEM', p_item_id);
    oan_notify_pkg.notify_role('MODERATOR', 'MODERATION_QUEUE', 'IP / confidentiality report',
      'An item was reported. It will be hidden automatically after 1 business day unless triaged.', 107);
    return l_id;
  end report_ip;

  procedure triage_ip(p_report_id in number, p_uphold in varchar2, p_note in varchar2) is
    l_rep  oan_ip_reports%rowtype;
    l_auth number;
  begin
    oan_util.assert(oan_security_pkg.is_moderator, 'Not authorized.', oan_util.c_err_forbidden);
    select * into l_rep from oan_ip_reports where id = p_report_id for update;
    select author_id into l_auth from oan_library_items where id = l_rep.item_id;
    oan_security_pkg.require_not_self(l_auth);
    update oan_ip_reports
       set status = case p_uphold when 'Y' then 'UPHELD' else 'DISMISSED' end,
           triaged_by = oan_util.viewer_id, triaged_at = systimestamp, decision_note = p_note
     where id = p_report_id;
    if p_uphold = 'Y' then
      update oan_library_items set status = 'HIDDEN', row_version = row_version + 1 where id = l_rep.item_id;
    elsif l_rep.status = 'AUTO_HIDDEN' then
      update oan_library_items set status = 'PUBLISHED' where id = l_rep.item_id and status = 'HIDDEN';
    end if;
    insert into oan_moderation_actions (object_type, object_id, queue, action, reason, actor_id, subject_user_id)
    values ('IP_REPORT', p_report_id, 'IP', case p_uphold when 'Y' then 'HIDE' else 'DISMISS' end,
            p_note, oan_util.viewer_id, l_auth);
    oan_audit_pkg.log('IP_REPORT_TRIAGE', 'LIBRARY_ITEM', l_rep.item_id, l_auth, json_object('upheld' value p_uphold));
  end triage_ip;

  procedure auto_hide_overdue_ip is
  begin
    for r in (select id, item_id from oan_ip_reports where status = 'NEW' and hide_due_at < systimestamp) loop
      update oan_library_items set status = 'HIDDEN' where id = r.item_id and status = 'PUBLISHED';
      update oan_ip_reports set status = 'AUTO_HIDDEN' where id = r.id;
      oan_audit_pkg.log('IP_REPORT_AUTO_HIDE', 'LIBRARY_ITEM', r.item_id);
    end loop;
  end auto_hide_overdue_ip;

  function import_csv(p_file_id in number) return number is
    l_batch  number;
    l_blob   blob;
    l_report json_array_t := json_array_t();
    l_ok     number := 0;
    l_err    number := 0;
    l_rows   number := 0;
    l_id     number;
    l_status varchar2(30);
  begin
    oan_security_pkg.require_admin;
    select content into l_blob from oan_files where id = p_file_id;
    insert into oan_import_batches (started_by, file_id) values (oan_util.viewer_id, p_file_id) returning id into l_batch;

    for r in (select line_number,
                     col001 title, col002 summary, col003 item_type, col004 url, col005 category,
                     col006 owner_type, col007 rights_basis, col008 rights_note, col009 tags,
                     col010 skill_level, col011 provider, col012 duration_minutes, col013 delivery_format,
                     col014 source_owner_confirmed
                from table(apex_data_parser.parse(p_content => l_blob, p_file_name => 'import.csv',
                                                  p_skip_rows => 1))) loop
      l_rows := l_rows + 1;
      begin
        -- Row-level validation (FR-19 P21: no row without a rights basis)
        oan_util.assert(r.title is not null, 'title is required');
        oan_util.assert(r.rights_basis in ('OAN_OWNED','CONTRIBUTOR_OWNED','LICENSED','PUBLICLY_AVAILABLE'),
                        'rights_basis missing or invalid');
        oan_util.assert(upper(r.item_type) in ('LINK','VIDEO'), 'only LINK/VIDEO rows can be imported from CSV');
        oan_util.assert(r.url is not null and regexp_like(r.url, '^https://', 'i'), 'url must start with https://');
        oan_util.assert(upper(r.category) != 'COMMUNITY_HISTORY' or upper(r.source_owner_confirmed) = 'Y',
                        'community history rows need source_owner_confirmed=Y');

        insert into oan_library_items (title, summary, item_type, url, category, owner_type, author_id,
                                       rights_basis, rights_note, attested, attested_at, status,
                                       skill_level, provider, duration_minutes, delivery_format,
                                       import_batch_id, source_owner_confirmed)
        values (r.title, r.summary, upper(r.item_type), r.url, upper(r.category), upper(r.owner_type),
                oan_util.viewer_id, upper(r.rights_basis), r.rights_note, 'Y', systimestamp, 'PENDING_REVIEW',
                upper(r.skill_level), r.provider, to_number(r.duration_minutes), r.delivery_format,
                l_batch, coalesce(upper(r.source_owner_confirmed), 'N'))
        returning id into l_id;

        insert into oan_library_item_tags (item_id, term_id)
        select distinct l_id, coalesce(t.canonical_id, t.id)
          from oan_taxonomy_terms t
         where upper(t.name) in (select upper(trim(column_value)) from table(apex_string.split(r.tags, ';')))
           and t.status in ('APPROVED','MERGED');

        screen(l_id);
        -- Imports are by an admin: clear, non-Sales/Product rows publish; others need a second admin
        select case when category in ('SALES','PRODUCT') or screening_status = 'FLAGGED'
                    then 'PENDING_SECOND_REVIEW' else 'PUBLISHED' end
          into l_status from oan_library_items where id = l_id;
        if l_status = 'PUBLISHED' then
          update oan_library_items set first_reviewer_id = oan_util.viewer_id where id = l_id;
          publish(l_id);
        else
          update oan_library_items set status = l_status, first_reviewer_id = oan_util.viewer_id where id = l_id;
        end if;
        l_ok := l_ok + 1;
        l_report.append(json_object('line' value r.line_number, 'status' value 'OK', 'item_id' value l_id, 'state' value l_status));
      exception
        when others then
          l_err := l_err + 1;
          l_report.append(json_object('line' value r.line_number, 'status' value 'ERROR',
                                      'message' value regexp_replace(sqlerrm, '^ORA-\d+: ', '')));
      end;
    end loop;

    update oan_import_batches set row_count = l_rows, ok_count = l_ok, error_count = l_err, report = l_report.to_clob
     where id = l_batch;
    oan_audit_pkg.log('LIBRARY_IMPORT', 'IMPORT_BATCH', l_batch, null,
                      json_object('rows' value l_rows, 'ok' value l_ok, 'errors' value l_err));
    return l_batch;
  end import_csv;

end oan_library_pkg;
/
