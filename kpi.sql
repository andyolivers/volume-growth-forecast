------------------------
----- Final Table ------
------------------------

create table kpis as 

-- Volumes --

with base as (
select distinct t.user_id, date(t.created_at) created_at, t.transfer_id, tm.transfer_type,
t.transfer_value as transfer_value_eur,
t.source_currency, t.target_currency, fx_gbp.rate as rate_eur_gbp, fx_gbp.inverse_rate as inverse_rate_eur_gbp,
t.transfer_value*fx_gbp.inverse_rate as transfer_value_gbp,
fx_inr.rate as rate_inr_gbp, fx_inr.inverse_rate as inverse_rate_inr_gbp,
(t.transfer_value*fx_gbp.inverse_rate)*fx_inr.inverse_rate as transfer_value_inr
from transfers t
left join transfers_meta tm on t.transfer_id = tm.transfer_id
left join fx_rates fx_gbp on date(t.created_at) = fx_gbp.currency_date and t.source_currency = fx_gbp.source_currency
and fx_gbp.target_currency = 'GBP'
left join fx_rates fx_inr on date(t.created_at) = fx_inr.currency_date
and fx_inr.target_currency = 'GBP' and fx_inr.source_currency = 'INR'
where t.flag_not_test = 1
)

, vol as (
select 
strftime('%Y-%m',created_at) as year_month,
transfer_type,
sum(transfer_value_eur) as transfer_value_eur,
sum(transfer_value_gbp) as transfer_value_gbp,
sum(transfer_value_inr) as transfer_value_inr
from base
group by 1,2
order by 1 desc
)

-- Revenue --

, base_rev as (
select distinct t.user_id, date(t.created_at) created_at, t.transfer_id, tm.transfer_type,
t.fee_value as revenue_value_eur,
t.source_currency, t.target_currency, fx_gbp.rate as rate_eur_gbp, fx_gbp.inverse_rate as inverse_rate_eur_gbp,
t.fee_value*fx_gbp.inverse_rate as revenue_value_gbp,
fx_inr.rate as rate_inr_gbp, fx_inr.inverse_rate as inverse_rate_inr_gbp,
(t.fee_value*fx_gbp.inverse_rate)*fx_inr.inverse_rate as revenue_value_inr
from transfers t
left join transfers_meta tm on t.transfer_id = tm.transfer_id
left join fx_rates fx_gbp on date(t.created_at) = fx_gbp.currency_date and t.source_currency = fx_gbp.source_currency
and fx_gbp.target_currency = 'GBP'
left join fx_rates fx_inr on date(t.created_at) = fx_inr.currency_date
and fx_inr.target_currency = 'GBP' and fx_inr.source_currency = 'INR'
where t.flag_not_test = 1
)

, rev as (
select 
strftime('%Y-%m',created_at) as year_month,
transfer_type,
sum(revenue_value_eur) as revenue_value_eur,
sum(revenue_value_gbp) as revenue_value_gbp,
sum(revenue_value_inr) as revenue_value_inr
from base_rev
group by 1,2
order by 1 desc
)

-- Transfers --

, base_transfers as (
select distinct t.user_id, t.created_at, t.transfer_id, tm.transfer_type
from transfers t
left join transfers_meta tm on t.transfer_id = tm.transfer_id
where t.flag_not_test = 1
)

, transf as (
select 
strftime('%Y-%m',created_at) as year_month,
transfer_type,
count(distinct transfer_id) as transfers
from base_transfers
group by 1,2
order by 1 desc
)

-- New users --

, base_nu as (
select distinct u.user_id, u.first_transfer_date, t.transfer_id, tm.transfer_type
from users u 
left join transfers t on u.first_transfer_id = t.transfer_id
left join transfers_meta tm on t.transfer_id = tm.transfer_id
where t.flag_not_test = 1
)

, new_users as (
select 
strftime('%Y-%m',first_transfer_date) as year_month,
transfer_type,
count(distinct user_id) as new_users
from base_nu
group by 1,2
order by 1 desc
)

-- Users --

, total_users as (
select a.*,SUM(new_users) OVER (ORDER BY year_month asc) as total_users,
ROW_NUMBER() OVER (partition by transfer_type ORDER BY year_month desc) as rn
from new_users a
)

-- Active Users Rate -- 
, active_users as (
select distinct t.user_id, t.created_at, t.transfer_id, tm.transfer_type
from transfers t
left join transfers_meta tm on t.transfer_id = tm.transfer_id
where t.flag_not_test = 1
)

, active_users_agg as (
select 
strftime('%Y-%m',created_at) as year_month,
transfer_type,
count(distinct user_id) as users
from active_users
group by 1,2
order by 1 desc)


-- End of last month users are the beginning of the next month users
, eom_users as (
select a.*, b.rn as rn_1, b.total_users as early_month_total_users
from total_users a
left join total_users b on a.transfer_type = b.transfer_type and a.rn+1 = b.rn
)

, activer_user_rate as (
select a.year_month, a.transfer_type, a.total_users, a.early_month_total_users, b.users as active_users,
(cast(b.users as float)/cast(a.early_month_total_users as float))*100 as activer_user_rate
from eom_users a 
left join active_users_agg b on a.year_month = b.year_month and a.transfer_type = b.transfer_type
)

select a.*,
b.revenue_value_eur,
b.revenue_value_gbp,
b.revenue_value_inr,
c.transfers,
d.new_users,
e.total_users as users,
f.activer_user_rate
from vol a 
left join rev b on a.year_month = b.year_month and a.transfer_type = b.transfer_type
left join transf c on a.year_month = c.year_month and a.transfer_type = c.transfer_type
left join new_users d on a.year_month = d.year_month and a.transfer_type = d.transfer_type
left join total_users e on a.year_month = e.year_month and a.transfer_type = e.transfer_type
left join activer_user_rate f on a.year_month = f.year_month and a.transfer_type = f.transfer_type

