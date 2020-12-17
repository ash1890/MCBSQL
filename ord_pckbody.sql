--------------------------------------------------------
--  File created - Friday-December-18-2020   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Package Body ORD_PCK
--------------------------------------------------------

  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "ORD_PCK" AS
/*****************************************************************************
ASEESURUN Package to import from XXBCM_ORDER_MGT raw format data into their respective tables
/******************************************************************************/
PROCEDURE clear_all_tables AS
--This procedure is used to clear all the tables before the migration occurs.
BEGIN
    DELETE FROM order_lines;
    
    DELETE FROM orders;
   
    DELETE FROM invoices;

    DELETE FROM suppliers;

    COMMIT;
 END clear_all_tables;
/******************************************************************************/
FUNCTION get_amount_number (p_amount IN VARCHAR2) RETURN NUMBER AS
--This function will take the varchar2 and convert into number
--Replace , by '' and 'S' by 5 and O by 0 and I by 1 for typo errors
m_amount NUMBER ;
BEGIN
  if p_amount is not null then
  SELECT
        to_number(replace(replace(replace(replace(upper(p_amount), ',', ''), 'S', 5), 'O', 0), 'I', 1))
    INTO m_amount
    FROM
        dual;
  end if;
  return(m_amount);
END get_amount_number;
/******************************************************************************/
FUNCTION get_date_from_string (p_date IN VARCHAR2) RETURN DATE AS
--This function will reformat the date accordingly and return it into a date format
--The file contains only two formats, DD-MON-YYYY and DD-MM-YYYY
--More formats can be added
    BEGIN
        IF p_date IS NOT NULL THEN
            BEGIN
                RETURN to_date(p_date, 'DD-MON-YYYY');
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;
            BEGIN
                RETURN to_date(p_date, 'DD-MM-YYYY');
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;
        END IF;

        RETURN NULL;
    END get_date_from_string;
/******************************************************************************/
Function get_payment_from_inv(p_invoice_reference in varchar2) return number as
m_inv_ref_pay number:=0;
begin

if length(p_invoice_reference)> 9 then
  --therefore it contains a payment number
  select to_number(replace(p_invoice_reference,substr(p_invoice_reference, 1, 9)||'.',''))
  into m_inv_ref_pay
  from dual;

  return(m_inv_ref_pay);
else  --it does not have any payment number return null  
return(null);
end if;


end get_payment_from_inv;
/******************************************************************************/
    PROCEDURE create_suppliers AS

        CURSOR c_suppliers IS
        SELECT DISTINCT
            supplier_name,
            supp_contact_name,
            supp_address,
            replace(replace(replace(replace(replace(TRIM(upper(supp_contact_number)), 'O', 0), 'S', 5), ' ', ''), '.', ''), 'I', 1
            ) contact_number,
            supp_email
        FROM
            xxbcm_order_mgt
        ORDER BY
            supplier_name;

        m_cnt NUMBER := 0;
    BEGIN
        FOR r1 IN c_suppliers LOOP
            m_cnt := m_cnt + 1;
            INSERT INTO suppliers VALUES (
                m_cnt,
                r1.supplier_name,
                r1.supp_contact_name,
                r1.supp_address,
                r1.contact_number,
                r1.supp_email,
                sysdate,
                user
            );

        END LOOP;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            raise_application_error(-20201, sqlerrm(sqlcode));
    END create_suppliers;
/******************************************************************************/

    PROCEDURE create_orders AS

        CURSOR c_ord IS
        SELECT
            order_ref,
            b.supplier_id,
            ord_pck.get_date_from_string(a.order_date) order_date,
            a.order_total_amount,
            a.order_description,
            a.order_status
        FROM
            xxbcm_order_mgt   a,
            suppliers         b
        WHERE
            a.order_line_amount IS NULL
            AND a.supplier_name = b.supplier_name
        ORDER BY
            a.order_ref;

    BEGIN
        FOR r1 IN c_ord LOOP
            INSERT INTO orders (
                order_ref,
                supplier_id,
                order_date,
                total_amount,
                ord_description,
                ord_status,
                created_date,
                created_by
            ) VALUES (
                r1.order_ref,
                r1.supplier_id,
                r1.order_date,
                get_amount_number(r1.order_total_amount),
                r1.order_description,
                r1.order_status,
                sysdate,
                user
            );

            create_order_lines(r1.order_ref);
        END LOOP;

        COMMIT;
    END;
/******************************************************************************/

    PROCEDURE create_order_lines (
        p_order_ref IN VARCHAR2
    ) AS

        CURSOR c_ord_lines IS
        SELECT
            a.order_ref           order_ref_line_id,
            a.order_description   line_description,
            order_status          line_status,
            ord_pck.get_amount_number(order_line_amount) line_amount,
            invoice_reference,
            invoice_date,
            invoice_status,
            invoice_hold_reason,
            invoice_amount,
            invoice_description
        FROM
            xxbcm_order_mgt a
        WHERE
            order_line_amount IS NOT NULL
            AND substr(a.order_ref, 1, 5) = p_order_ref
        ORDER BY
            order_ref;

        m_cnt_seq NUMBER := 1;
        m_inv_seq invoices.inv_seq%type;
        m_inv_reference invoices.inv_reference%type;

    BEGIN
        FOR r1 IN c_ord_lines LOOP
            INSERT INTO order_lines (
                ord_line_seq,
                order_ref,
                order_ref_line_id,
                line_description,
                line_status,
                line_amount,
                created_date,
                created_by
            ) VALUES (
                m_cnt_seq,
                p_order_ref,
                to_number(replace(r1.order_ref_line_id, p_order_ref || '-', '')),
                r1.line_description,
                r1.line_status,
                r1.line_amount,
                sysdate,
                user
            );

            --create the invoice
            if r1.invoice_reference is not null then
            create_invoices (r1.invoice_reference,get_date_from_string(r1.invoice_date),r1.invoice_status,r1.invoice_hold_reason,
            ord_pck.get_amount_number(r1.invoice_amount),r1.invoice_description,m_inv_seq,m_inv_reference);

            update order_lines
            set inv_seq=m_inv_seq,inv_reference=m_inv_reference
            where ord_line_seq=m_cnt_seq
            and order_ref=p_order_ref;
            end if;


            m_cnt_seq := m_cnt_seq + 1;
        END LOOP;
    END create_order_lines;

/******************************************************************************/

    PROCEDURE create_invoices (
        p_invoice_reference     IN    VARCHAR2,
        p_invoice_date          IN    DATE,
        p_invoice_status        IN    VARCHAR2,
        p_invoice_hold_reason   IN    VARCHAR2,
        p_invoice_amount        IN    NUMBER,
        p_invoice_description   IN    VARCHAR2,
        p_inv_seq               OUT   NUMBER,
        p_inv_reference         OUT   VARCHAR2
    ) AS
        m_inv_seq NUMBER := 0;
    BEGIN
--check if invoice_exists in invoice table

            SELECT
                nvl(MAX(inv_seq),0)
            INTO m_inv_seq
            FROM
                invoices
            WHERE
                inv_reference = substr(p_invoice_reference, 1, 9);

   --add 1 before insert

        m_inv_seq := m_inv_seq + 1;
      INSERT INTO invoices (
    inv_seq,
    inv_reference,
    inv_ref_pay,
    inv_date,
    inv_status,
    inv_hold_reason,
    inv_amount,
    inv_description,
    inv_created_date,
    inv_created_by
) VALUES (
    m_inv_seq,
    substr(p_invoice_reference, 1, 9),
    get_payment_from_inv(p_invoice_reference),
    p_invoice_date,
    p_invoice_status,
    p_invoice_hold_reason,
    p_invoice_amount,
    p_invoice_description,
    sysdate,
    user
);

p_inv_seq:=m_inv_seq;
p_inv_reference:=substr(p_invoice_reference, 1, 9);

    END create_invoices;

/******************************************************************************/
PROCEDURE migration_process AS
  BEGIN
  dbms_output.put_line('Start migration process');
    clear_all_tables;
  dbms_output.put_line('All tables cleared');
    
    create_suppliers; 
  dbms_output.put_line('All suppliers created');
  
    create_orders;
  dbms_output.put_line('Orders successfully created');
  dbms_output.put_line('Migration over');
  exception when others then
  raise_application_error(-20201,sqlerrm(sqlcode));
  END migration_process;
/******************************************************************************/
Procedure distinct_invoices_with_total as

--summary of Orders with their corresponding list of distinct invoices and their total amount 
cursor c_results is
SELECT
    a.order_ref,
    to_number(substr(a.order_ref, - 3, 5)) ord_ref,
    to_char(a.order_date, 'MON-YY') order_period,
    initcap(b.supplier_name) supp_name,
    to_char(a.total_amount, '99,999,990.00') tot_amt,
    ord_status        ord_status,
    c.inv_reference   inv_ref,
    to_char(c.invoice_amount, '99,999,990.00') inv_amt
FROM
    orders      a,
    suppliers   b,
    (
        SELECT DISTINCT
            ( inv_reference ),
            SUM(inv_amount) invoice_amount
        FROM
            invoices
        GROUP BY
            inv_reference
    ) c
WHERE
    a.supplier_id = b.supplier_id
    AND substr(c.inv_reference, 5, 5) = a.order_ref
ORDER BY
    order_date DESC;
m_action varchar2(25);
begin
    dbms_output.put_line('-----------------------------------------------LIST OF DISTINCT INVOICES AND THEIR TOTAL AMOUNT------------------------------------------------------------------------------');
    dbms_output.put_line('Order Reference  Order Period  Supplier Name                Order Total Amount   Order Status     Invoice Reference   Invoice Total Amount    Action');
    dbms_output.put_line('------------------------------------------------------------------------------------------------------------------------------------------------------------------------------');
  for r1 in c_results loop
    m_action:=get_action_status(r1.order_ref);
    dbms_output.put_line(RPAD(r1.ord_ref,18)||RPAD(r1.order_period,13)||RPAD(r1.supp_name,30)||RPAD(r1.tot_amt,22)||RPAD(r1.ord_status,17)||rpad(r1.inv_ref,20)||rpad(r1.inv_amt,22)||m_action);
    dbms_output.put_line('------------------------------------------------------------------------------------------------------------------------------------------------------------------------------');
  end loop;  
end distinct_invoices_with_total;

/*******************************************************************************/
Procedure get_nth_highest_order_amount(p_number in number) as
--Return details for the Nth highest Order Total Amount from the list. 
cursor c_output is
select a.order_ref,upper(b.supplier_name) supp_name,to_char(a.order_date,'fmMonth DD,YYYY') ord_date,a.ord_status,to_char(a.total_amount,'99,999,990.00') amt
from orders a,suppliers b
where a.supplier_id=b.supplier_id
order by total_amount desc;

m_count number:=0;
m_invref varchar2(500);
begin
 for r1 in c_output loop
   m_count:=m_count+1;
   
   if m_count=p_number then
     --get all invoices for that order
     m_invref:=get_invoices(r1.order_ref);
   
    dbms_output.put_line('-----------------------------------------------'||to_char(to_date(p_number,'DD'),'DDSPTH')||' HIGHEST ORDER TOTAL AMOUNT----------------------------------------------------------');
    dbms_output.put_line('Order Reference     Order Date          Supplier Name        Order Total Amount   Order Status  Invoice References');
    dbms_output.put_line('--------------------------------------------------------------------------------------------------------------------------------------------------');
    dbms_output.put_line(RPAD(r1.order_ref,18)||RPAD(r1.ord_date,21)||RPAD(r1.supp_name,20)||RPAD(r1.amt,25)||RPAD(r1.ord_status,15)||m_invref);
   exit;
   end if;
 end loop;




end get_nth_highest_order_amount;
/*******************************************************************************/
Function get_invoices(p_order_ref in varchar2) return varchar2 as
--Get list of invoices per order
cursor c1 is 
select distinct(decode(a.inv_ref_pay,null,a.inv_reference,a.inv_reference||'.'||a.inv_ref_pay)) inv
from invoices a,order_lines b
where a.inv_seq=b.inv_seq
and a.inv_reference=b.inv_reference
and b.order_ref=p_order_ref;


m_invoicerefs varchar2(500);
begin
 for r1 in c1 loop
if m_invoicerefs is null then
m_invoicerefs :=r1.inv;
else
m_invoicerefs :=m_invoicerefs||','||r1.inv;
end if;
end loop;
return(m_invoicerefs);

end get_invoices;
/*******************************************************************************/
Procedure list_suppliers_with_orders(p_date_from in date,p_date_to in date) as
--List all suppliers with their respective number of orders and total amount ordered from them between any period
cursor c_suppliers is
select a.supplier_name,a.contact_name,contact_number,count('*') total_orders,to_char(sum(b.total_amount),'99,999,990.00') total_amt
from suppliers a,orders b
where a.supplier_id=b.supplier_id
and b.order_date between p_date_from and p_date_to
group by a.supplier_name,a.contact_name,contact_number;
m_contact1 varchar2(15);
m_contact2 varchar2(15);
begin
 dbms_output.put_line('--------------------NUMBER OF ORDERS AND TOTAL AMOUNT ORDERED FROM PERIOD '||p_date_from||' to '||p_date_to||'----------------------------------------------------------');
 dbms_output.put_line('--------------------------------------------------------------------------------------------------------------------------------------------------');
 dbms_output.put_line('   Supplier Name            Supplier Contact Name   Supplier Contact No.1   Supplier Contact No.2   Total Orders   Order Total Amount');
for r1 in c_suppliers loop
   get_detailed_contact(r1.contact_number,m_contact1,m_contact2);
   dbms_output.put_line('--------------------------------------------------------------------------------------------------------------------------------------------------');
   dbms_output.put_line(RPAD(r1.supplier_name,30)||RPAD(r1.contact_name,25)||RPAD(m_contact1,25)||RPAD(m_contact2,25)||RPAD(r1.total_orders,10)||r1.total_amt);


end loop;

end list_suppliers_with_orders;
/*******************************************************************************/
Procedure get_detailed_contact(p_contact_number in varchar2,p_out_contact1 out varchar2,p_out_contact2 out varchar2) as
--This procedure will check if there is  a , in the phone number
--It will then extract the phone numbers and format them accordingly.
m_contact1 varchar2(15):='';
m_contact2 varchar2(15):='';
begin
  if instr(p_contact_number,',')=0 then
    m_contact1:=p_contact_number;
    m_contact2:=' ';
  else
    m_contact1:=replace(substr(p_contact_number,1,instr(p_contact_number,',')),',','');
    m_contact2:=replace(substr(p_contact_number,instr(p_contact_number,','),length(p_contact_number)),',','');
  end if;
  if length(m_contact1) = 7 then
    m_contact1:=to_char(substr(m_contact1, 1, 3) || '-' || substr(m_contact1, 4, 4));
  elsif length(m_contact1)=8 then
    m_contact1:=to_char(substr(m_contact1, 1, 4) || '-' || substr(m_contact1, 4, 5));
  else
    m_contact1:=' ';
  end if;
  if length(m_contact2) = 7 then
    m_contact2:=to_char(substr(m_contact2, 1, 3) || '-' || substr(m_contact2, 4, 4));
  elsif length(m_contact2)=8 then
    m_contact2:=to_char(substr(m_contact2, 1, 4) || '-' || substr(m_contact2, 4, 5));
  else
    m_contact2:=' ';
  end if;
  p_out_contact1:=m_contact1;
  p_out_contact2:=m_contact2;
end get_detailed_contact;
/*******************************************************************************/
Function get_action_status (p_order_ref in varchar2) return varchar2 as
m_action varchar2(25);
m_blank number:=0;
m_paid number:=0;
m_pending number:=0;
begin
select count('*')
into m_blank
from order_lines
where order_ref=p_order_ref
and inv_reference is null;  --This means there is no invoice attached to this line, status is blank

if m_blank >0 then
  return('To verify');
else
  select sum(decode(upper(inv_status),'PAID',1,0)) PAID,sum(decode(upper(inv_status),'PENDING',1,0)) PENDING
  into m_paid ,m_pending
  from invoices
  where substr(inv_reference,5,5) = p_order_ref;
end if;
if m_pending>0 then  --if any invoice is pending then
return('To follow up');
else  --all must thave been paid
return('OK');
end if;

return(m_action);
end get_action_status;

END ord_pck;

/
