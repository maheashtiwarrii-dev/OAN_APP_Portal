--------------------------------------------------------------------------------
-- 105 Notifications and message search (W4.1, W4.3; FR-23, FR-18, R26; 14 Oct 2026). Re-runnable.
--   * Read notifications are purged after 180 days (W4.3, was 365).
--   * OAN_MSG_TEXT_IX: message search inside the member's own conversations only (S16); messages never
--     appear in global search (R20).
--   * Slack and WhatsApp channels were removed from the requirements on 16 Oct 2026 (Q38); 110 removes the
--     channel objects from databases that had them.
--------------------------------------------------------------------------------
------------------------------------------------------------ message search --
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_indexes where index_name = 'OAN_MSG_TEXT_IX';
  if l_cnt = 0 then
    execute immediate q'[create index oan_msg_text_ix on oan_messages (body)
      indextype is ctxsys.context
      parameters ('lexer OAN_LEXER wordlist OAN_WORDLIST sync (every "freq=minutely;interval=2")')]';
  end if;
end;
/

----------------------------------------------------------- config --
merge into oan_config c
using (select 'MESSAGE_POLL_SECONDS' k, '20' v, 'NUMBER' t, 'Seconds between new-message checks on page 40 (FR-18, unread within 60s)' d from dual) s
   on (c.config_key = s.k)
 when not matched then insert (config_key, config_value, value_type, description) values (s.k, s.v, s.t, s.d);

-- Retention (R26): read notifications 180 days
merge into oan_pd_tables t
using (select 'OAN_NOTIFICATIONS' n, 180 d, 'CREATED_AT' c, q'[is_read = 'Y']' w, 'Read in-app notifications (W4.3)' r from dual) s
   on (t.table_name = s.n)
 when matched then update set t.retention_days = s.d, t.retention_column = s.c, t.retention_where = s.w,
                              t.retention_note = s.r;
commit;
