-- =============================================================================
--  OAN_NOTIFY_API - Notification and email service
--  Oracle Alumni Network (OAN)  |  Package skeleton v1.0
--  Companion to: Oracle-Alumni-Network-Functional-Specification v1.0 (FR-16)
--  Schema owner: OAN_APP   |   APEX 23.2+   |   Oracle Database 19c/23ai
--
--  Central notification service. Page logic and triggers call NOTIFY; this
--  package honours per-member channel preferences, writes the in-app record,
--  and queues email for the scheduled sender.
-- =============================================================================

CREATE OR REPLACE PACKAGE OAN_NOTIFY_API AS

  -- ---------------------------------------------------------------------------
  -- Public types
  -- ---------------------------------------------------------------------------
  TYPE t_number_tab IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

  -- ---------------------------------------------------------------------------
  -- Constants - notification types
  -- ---------------------------------------------------------------------------
  c_type_message       CONSTANT VARCHAR2(60) := 'MESSAGE';
  c_type_follow        CONSTANT VARCHAR2(60) := 'FOLLOW';
  c_type_referral      CONSTANT VARCHAR2(60) := 'REFERRAL';
  c_type_request       CONSTANT VARCHAR2(60) := 'REQUEST_STATUS';
  c_type_event         CONSTANT VARCHAR2(60) := 'EVENT_REMINDER';
  c_type_application   CONSTANT VARCHAR2(60) := 'APPLICATION';
  c_type_mention       CONSTANT VARCHAR2(60) := 'MENTION';
  c_type_system        CONSTANT VARCHAR2(60) := 'SYSTEM';

  -- ---------------------------------------------------------------------------
  -- Core
  -- ---------------------------------------------------------------------------
  -- Creates a notification, honouring the member's channel preferences.
  PROCEDURE notify (
    p_member_id   IN NUMBER,
    p_type        IN VARCHAR2,
    p_title       IN VARCHAR2,
    p_body        IN VARCHAR2 DEFAULT NULL,
    p_entity_type IN VARCHAR2 DEFAULT NULL,
    p_entity_id   IN NUMBER   DEFAULT NULL
  );

  -- Bulk variant for a group of members.
  PROCEDURE notify_many (
    p_member_ids  IN t_number_tab,
    p_type        IN VARCHAR2,
    p_title       IN VARCHAR2,
    p_body        IN VARCHAR2 DEFAULT NULL,
    p_entity_type IN VARCHAR2 DEFAULT NULL,
    p_entity_id   IN NUMBER   DEFAULT NULL
  );

  -- Returns TRUE when the member wants the given channel for the type.
  FUNCTION wants_channel (
    p_member_id IN NUMBER,
    p_type      IN VARCHAR2,
    p_channel   IN VARCHAR2   -- 'EMAIL' or 'IN_APP'
  ) RETURN BOOLEAN;

  -- ---------------------------------------------------------------------------
  -- Read state
  -- ---------------------------------------------------------------------------
  FUNCTION unread_count (p_member_id IN NUMBER) RETURN NUMBER;

  PROCEDURE mark_read (p_notification_id IN NUMBER);

  PROCEDURE mark_all_read (p_member_id IN NUMBER);

  -- ---------------------------------------------------------------------------
  -- Event-specific helpers
  -- ---------------------------------------------------------------------------
  PROCEDURE notify_message (
    p_conversation_id IN NUMBER,
    p_message_id      IN NUMBER
  );

  PROCEDURE notify_follow (
    p_follower_member_id IN NUMBER,
    p_followed_member_id IN NUMBER
  );

  PROCEDURE notify_referral (p_referral_id IN NUMBER);

  PROCEDURE notify_request_status (p_request_id IN NUMBER);

  PROCEDURE notify_application_status (p_application_id IN NUMBER);

  PROCEDURE notify_event_reminder (p_event_id IN NUMBER);

  -- ---------------------------------------------------------------------------
  -- Scheduled sender
  -- ---------------------------------------------------------------------------
  -- Emails pending notifications; returns the number sent.
  FUNCTION send_pending_emails (p_batch_size IN NUMBER DEFAULT 50) RETURN NUMBER;

  -- Marks a notification as emailed (called after the mail is handed to the
  -- mail queue).
  PROCEDURE mark_emailed (p_notification_id IN NUMBER);

END OAN_NOTIFY_API;
/

CREATE OR REPLACE PACKAGE BODY OAN_NOTIFY_API AS

  -- ---------------------------------------------------------------------------
  -- Private helpers
  -- ---------------------------------------------------------------------------
  PROCEDURE audit_notify (p_action IN VARCHAR2, p_record_id IN NUMBER, p_detail IN VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO OAN_AUDIT_LOG (table_name, record_id, action, changed_by, new_values)
    VALUES ('OAN_NOTIFICATIONS', p_record_id, p_action,
            NVL(SYS_CONTEXT('APEX$SESSION','APP_USER'), USER),
            '{"detail":"' || REPLACE(p_detail, '"', '''') || '"}');
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END audit_notify;

  FUNCTION member_email (p_member_id IN NUMBER) RETURN VARCHAR2 IS
    l_email VARCHAR2(255);
  BEGIN
    SELECT email INTO l_email
      FROM OAN_MEMBERS
     WHERE member_id = p_member_id;
    RETURN l_email;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN NULL;
  END member_email;

  -- ---------------------------------------------------------------------------
  -- Core
  -- ---------------------------------------------------------------------------
  PROCEDURE notify (
    p_member_id   IN NUMBER,
    p_type        IN VARCHAR2,
    p_title       IN VARCHAR2,
    p_body        IN VARCHAR2 DEFAULT NULL,
    p_entity_type IN VARCHAR2 DEFAULT NULL,
    p_entity_id   IN NUMBER   DEFAULT NULL
  ) IS
    l_notification_id NUMBER;
    l_in_app BOOLEAN := wants_channel(p_member_id, p_type, 'IN_APP');
  BEGIN
    IF p_member_id IS NULL OR NOT l_in_app THEN
      RETURN;   -- member has switched this type off, or the recipient is unknown
    END IF;

    INSERT INTO OAN_NOTIFICATIONS
      (member_id, notification_type, title, body, entity_type, entity_id, is_read_yn, created_on)
    VALUES
      (p_member_id, p_type, p_title, p_body, p_entity_type, p_entity_id, 'N', SYSTIMESTAMP)
    RETURNING notification_id INTO l_notification_id;

    audit_notify('NOTIFY', l_notification_id, p_type || ':' || p_title);
  EXCEPTION
    WHEN OTHERS THEN
      -- Notifications are best effort: never fail the business transaction.
      NULL;
  END notify;

  PROCEDURE notify_many (
    p_member_ids  IN t_number_tab,
    p_type        IN VARCHAR2,
    p_title       IN VARCHAR2,
    p_body        IN VARCHAR2 DEFAULT NULL,
    p_entity_type IN VARCHAR2 DEFAULT NULL,
    p_entity_id   IN NUMBER   DEFAULT NULL
  ) IS
  BEGIN
    IF p_member_ids IS NULL OR p_member_ids.COUNT = 0 THEN
      RETURN;
    END IF;
    FOR i IN 1 .. p_member_ids.COUNT LOOP
      notify(p_member_ids(i), p_type, p_title, p_body, p_entity_type, p_entity_id);
    END LOOP;
  END notify_many;

  FUNCTION wants_channel (
    p_member_id IN NUMBER,
    p_type      IN VARCHAR2,
    p_channel   IN VARCHAR2
  ) RETURN BOOLEAN IS
    l_email VARCHAR2(1);
    l_inapp VARCHAR2(1);
  BEGIN
    SELECT email_yn, in_app_yn
      INTO l_email, l_inapp
      FROM OAN_NOTIFICATION_PREFS
     WHERE member_id = p_member_id
       AND notification_type = p_type;

    IF UPPER(p_channel) = 'EMAIL' THEN
      RETURN l_email = 'Y';
    END IF;
    RETURN l_inapp = 'Y';
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      -- Default: in-app on, email on for transactional types.
      IF UPPER(p_channel) = 'EMAIL' THEN
        RETURN p_type IN (c_type_message, c_type_referral, c_type_request, c_type_event);
      END IF;
      RETURN TRUE;
  END wants_channel;

  -- ---------------------------------------------------------------------------
  -- Read state
  -- ---------------------------------------------------------------------------
  FUNCTION unread_count (p_member_id IN NUMBER) RETURN NUMBER IS
    l_cnt NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l_cnt
      FROM OAN_NOTIFICATIONS
     WHERE member_id = p_member_id
       AND is_read_yn = 'N';
    RETURN NVL(l_cnt, 0);
  END unread_count;

  PROCEDURE mark_read (p_notification_id IN NUMBER) IS
  BEGIN
    UPDATE OAN_NOTIFICATIONS
       SET is_read_yn = 'Y'
     WHERE notification_id = p_notification_id
       AND is_read_yn = 'N';
  END mark_read;

  PROCEDURE mark_all_read (p_member_id IN NUMBER) IS
  BEGIN
    UPDATE OAN_NOTIFICATIONS
       SET is_read_yn = 'Y'
     WHERE member_id = p_member_id
       AND is_read_yn = 'N';
  END mark_all_read;

  -- ---------------------------------------------------------------------------
  -- Event-specific helpers
  -- ---------------------------------------------------------------------------
  PROCEDURE notify_message (
    p_conversation_id IN NUMBER,
    p_message_id      IN NUMBER
  ) IS
    l_sender_id   NUMBER;
    l_sender_name VARCHAR2(200);
    l_title       VARCHAR2(300);
  BEGIN
    SELECT m.sender_member_id, m.first_name || ' ' || m.last_name
      INTO l_sender_id, l_sender_name
      FROM OAN_MESSAGES msg
      JOIN OAN_MEMBERS m ON m.member_id = msg.sender_member_id
     WHERE msg.message_id = p_message_id;

    l_title := 'New message from ' || l_sender_name;

    FOR r IN (SELECT cm.member_id
                FROM OAN_CONVERSATION_MEMBERS cm
               WHERE cm.conversation_id = p_conversation_id
                 AND NVL(cm.muted_yn, 'N') = 'N'
                 AND cm.member_id <> NVL(l_sender_id, -1))
    LOOP
      notify(r.member_id, c_type_message, l_title, NULL, 'MESSAGE', p_message_id);
    END LOOP;
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END notify_message;

  PROCEDURE notify_follow (
    p_follower_member_id IN NUMBER,
    p_followed_member_id IN NUMBER
  ) IS
    l_name VARCHAR2(200);
  BEGIN
    SELECT first_name || ' ' || last_name INTO l_name
      FROM OAN_MEMBERS WHERE member_id = p_follower_member_id;

    notify(p_followed_member_id, c_type_follow, l_name || ' is now following you',
           NULL, 'MEMBER', p_follower_member_id);
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END notify_follow;

  PROCEDURE notify_referral (p_referral_id IN NUMBER) IS
    l_target NUMBER;
    l_job    VARCHAR2(250);
    l_name   VARCHAR2(200);
  BEGIN
    SELECT rr.target_member_id, j.job_title,
           m.first_name || ' ' || m.last_name
      INTO l_target, l_job, l_name
      FROM OAN_REFERRAL_REQUESTS rr
      JOIN OAN_JOBS j ON j.job_id = rr.job_id
      JOIN OAN_MEMBERS m ON m.member_id = rr.requester_member_id
     WHERE rr.referral_id = p_referral_id;

    notify(l_target, c_type_referral,
           l_name || ' has requested a referral',
           'Role: ' || l_job, 'REFERRAL', p_referral_id);
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END notify_referral;

  PROCEDURE notify_request_status (p_request_id IN NUMBER) IS
    l_member NUMBER;
    l_ref    VARCHAR2(30);
    l_status VARCHAR2(30);
  BEGIN
    SELECT member_id, reference_no, status
      INTO l_member, l_ref, l_status
      FROM OAN_SERVICE_REQUESTS
     WHERE request_id = p_request_id;

    notify(l_member, c_type_request,
           'Your request ' || l_ref || ' is now ' || l_status,
           NULL, 'SERVICE_REQUEST', p_request_id);
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END notify_request_status;

  PROCEDURE notify_application_status (p_application_id IN NUMBER) IS
    l_member NUMBER;
    l_job    VARCHAR2(250);
    l_status VARCHAR2(30);
  BEGIN
    SELECT ja.member_id, j.job_title, ja.status
      INTO l_member, l_job, l_status
      FROM OAN_JOB_APPLICATIONS ja
      JOIN OAN_JOBS j ON j.job_id = ja.job_id
     WHERE ja.application_id = p_application_id;

    notify(l_member, c_type_application,
           'Application update: ' || l_job,
           'Your application status is now ' || l_status,
           'JOB_APPLICATION', p_application_id);
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END notify_application_status;

  PROCEDURE notify_event_reminder (p_event_id IN NUMBER) IS
    l_title VARCHAR2(300);
    l_start TIMESTAMP;
  BEGIN
    SELECT title, start_dt INTO l_title, l_start
      FROM OAN_EVENTS WHERE event_id = p_event_id;

    FOR r IN (SELECT member_id
                FROM OAN_EVENT_REGISTRATIONS
               WHERE event_id = p_event_id
                 AND status = 'REGISTERED')
    LOOP
      notify(r.member_id, c_type_event,
             'Reminder: ' || l_title,
             'Starts ' || TO_CHAR(l_start, 'DD Mon YYYY HH24:MI'),
             'EVENT', p_event_id);
    END LOOP;
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END notify_event_reminder;

  -- ---------------------------------------------------------------------------
  -- Scheduled sender
  -- ---------------------------------------------------------------------------
  FUNCTION send_pending_emails (p_batch_size IN NUMBER DEFAULT 50) RETURN NUMBER IS
    l_sent NUMBER := 0;
  BEGIN
    -- The email flag is derived from the member's preferences; a notification
    -- is emailed once. APEX_MAIL is used when available, otherwise the mail is
    -- handed to the environment's mail queue.
    FOR r IN (SELECT n.notification_id, n.member_id, n.title, n.body,
                     m.email
                FROM OAN_NOTIFICATIONS n
                JOIN OAN_MEMBERS m ON m.member_id = n.member_id
               WHERE n.is_read_yn = 'N'
                 AND m.email IS NOT NULL
                 AND m.member_status = 'ACTIVE'
               ORDER BY n.created_on
               FETCH FIRST p_batch_size ROWS ONLY)
    LOOP
      IF wants_channel(r.member_id, 'MESSAGE', 'EMAIL')
         OR wants_channel(r.member_id, 'REFERRAL', 'EMAIL') THEN
        BEGIN
          APEX_MAIL.SEND (
            p_to        => r.email,
            p_from      => 'no-reply@oracle-alumni.example',
            p_subj      => r.title,
            p_body      => NVL(r.body, r.title) || UTL_TCP.CRLF || UTL_TCP.CRLF ||
                           'Sign in to the Oracle Alumni Network to view this notification.'
          );
          APEX_MAIL.PUSH_QUEUE;
          l_sent := l_sent + 1;
        EXCEPTION
          WHEN OTHERS THEN
            NULL;   -- one bad address must not stop the batch
        END;
      END IF;
    END LOOP;

    RETURN l_sent;
  END send_pending_emails;

  PROCEDURE mark_emailed (p_notification_id IN NUMBER) IS
  BEGIN
    audit_notify('EMAIL_SENT', p_notification_id, 'queued');
  END mark_emailed;

END OAN_NOTIFY_API;
/

-- =============================================================================
--  Scheduled jobs
-- =============================================================================
BEGIN
  DBMS_SCHEDULER.CREATE_JOB (
    job_name        => 'OAN_JOB_NOTIFY_EMAIL',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN OAN_NOTIFY_API.send_pending_emails(50); END;',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=MINUTELY; INTERVAL=15',
    enabled         => FALSE);
EXCEPTION
  WHEN OTHERS THEN NULL;
END;
/

BEGIN
  DBMS_SCHEDULER.CREATE_JOB (
    job_name        => 'OAN_JOB_EVENT_REMINDER',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN FOR r IN (SELECT event_id FROM OAN_EVENTS WHERE start_dt BETWEEN SYSTIMESTAMP AND SYSTIMESTAMP + 2) LOOP OAN_NOTIFY_API.notify_event_reminder(r.event_id); END LOOP; END;',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=DAILY; BYHOUR=7',
    enabled         => FALSE);
EXCEPTION
  WHEN OTHERS THEN NULL;
END;
/

-- =============================================================================
--  Grant execute to the APEX parsing schema (adjust to the environment)
-- =============================================================================
-- GRANT EXECUTE ON OAN_NOTIFY_API TO OAN_APEX;
