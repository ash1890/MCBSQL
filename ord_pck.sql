--------------------------------------------------------
--  File created - Friday-December-18-2020   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Package ORD_PCK
--------------------------------------------------------

  CREATE OR REPLACE EDITIONABLE PACKAGE "ORD_PCK" as 
/******************************************************************************/
Procedure clear_all_tables;
/******************************************************************************/
Function get_amount_number(p_amount in varchar2) return number;
/******************************************************************************/
Function get_date_from_string(p_date in varchar2) return date ;
/******************************************************************************/
Function get_payment_from_inv(p_invoice_reference in varchar2) return number ;
/******************************************************************************/
Procedure create_order_lines(p_order_ref in varchar2);
/******************************************************************************/
Procedure create_invoices(p_invoice_reference in varchar2,p_invoice_date in date,p_invoice_status in varchar2,
p_invoice_hold_reason in varchar2,p_invoice_amount in number,p_invoice_description in varchar2,p_inv_seq out number,
p_inv_reference out varchar2);
/******************************************************************************/
Procedure create_suppliers ;
/******************************************************************************/
Procedure migration_process;
/******************************************************************************/
Procedure distinct_invoices_with_total ;
/******************************************************************************/
Procedure get_nth_highest_order_amount(p_number in number);
/******************************************************************************/
Function get_invoices(p_order_ref in varchar2) return varchar2;
/******************************************************************************/
Procedure list_suppliers_with_orders(p_date_from in date,p_date_to in date) ;
/******************************************************************************/
Procedure get_detailed_contact(p_contact_number in varchar2,p_out_contact1 out varchar2,p_out_contact2 out varchar2);
/******************************************************************************/
Function get_action_status (p_order_ref in varchar2) return varchar2;
/******************************************************************************/
end ord_pck;

/
