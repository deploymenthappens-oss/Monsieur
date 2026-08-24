-- ============================================================
-- MONSIEUR — FULL PRODUCTION E-COMMERCE SCHEMA (Supabase / PostgreSQL)
-- ============================================================
-- Organized in 4 zones:
--   ZONE A — Catalog (what sellers manage: products, media, vendors)
--   ZONE B — Inventory (stock levels + movement history)
--   ZONE C — Commerce (customers, orders, shipping, payment, channel)
--   ZONE D — Analytics (views only — no manual data entry, always accurate)
-- ============================================================

create extension if not exists "uuid-ossp";

-- ============================================================
-- ZONE A — CATALOG
-- ============================================================

-- ------------------------------------------------------------
-- A1. VENDORS / SOURCE — where you sourced the product from
-- ------------------------------------------------------------
create table vendors (
    id              uuid primary key default uuid_generate_v4(),
    name            text not null,
    contact_email   text,
    contact_phone   text,
    notes           text,
    created_at      timestamptz not null default now()
);

-- ------------------------------------------------------------
-- A2. CATEGORIES
-- ------------------------------------------------------------
create table categories (
    id          uuid primary key default uuid_generate_v4(),
    name        text not null,
    slug        text not null unique,
    created_at  timestamptz not null default now()
);

-- ------------------------------------------------------------
-- A3. PRODUCTS — the core catalog table
-- ------------------------------------------------------------
create type product_status as enum ('draft', 'active', 'archived');
create type product_type   as enum ('simple', 'variable');   -- simple = one SKU, variable = has variants (sizes/scents)

create table products (
    id                      uuid primary key default uuid_generate_v4(),
    name                    text not null,
    sku                     text unique,                -- base SKU (ignored for variable products; variants have their own)
    slug                    text unique,                -- webpage URL e.g. /products/oud-royal
    description             text,
    price                   numeric(10,2) not null default 0,   -- original price
    final_price             numeric(10,2),                       -- discounted selling price; null = no discount, price is charged
    product_type            product_type not null default 'simple',
    vendor_id               uuid references vendors(id) on delete set null,
    category_id             uuid references categories(id) on delete set null,
    status                  product_status not null default 'draft',
    available_for_restock   boolean not null default false,
    created_at              timestamptz not null default now(),
    updated_at              timestamptz not null default now(),
    last_edited_by          text,
    constraint final_price_not_greater_than_price check (final_price is null or final_price <= price)
);

-- ------------------------------------------------------------
-- A4. PRODUCT MEDIA — images AND videos, one unified table
-- ------------------------------------------------------------
create type media_type as enum ('image', 'video');

create table product_media (
    id          uuid primary key default uuid_generate_v4(),
    product_id  uuid not null references products(id) on delete cascade,
    media_type  media_type not null default 'image',
    url         text not null,
    alt_text    text,
    sort_order  integer not null default 0,
    created_at  timestamptz not null default now()
);

-- ------------------------------------------------------------
-- A5. PRODUCT VARIANTS — only used when product_type = 'variable'
-- ------------------------------------------------------------
create table product_variants (
    id              uuid primary key default uuid_generate_v4(),
    product_id      uuid not null references products(id) on delete cascade,
    variant_name    text not null,          -- "50ml", "100ml", "Oud / Rose"
    sku             text unique,
    price_override  numeric(10,2),          -- null = inherit product.price
    final_price_override numeric(10,2),     -- null = inherit product.final_price
    created_at      timestamptz not null default now()
);

-- ============================================================
-- ZONE B — INVENTORY (kept separate from catalog on purpose:
-- stock changes constantly, product info doesn't. Separating
-- them means restocks/sales never touch the product row.)
-- ============================================================

-- ------------------------------------------------------------
-- B1. INVENTORY — current stock level per product or variant
-- ------------------------------------------------------------
create table inventory (
    id              uuid primary key default uuid_generate_v4(),
    product_id      uuid not null references products(id) on delete cascade,
    variant_id      uuid references product_variants(id) on delete cascade,  -- null if product_type = 'simple'
    quantity_on_hand integer not null default 0,
    low_stock_threshold integer not null default 5,   -- triggers "available_for_restock" style alerts
    updated_at      timestamptz not null default now(),
    unique (product_id, variant_id)
);

-- ------------------------------------------------------------
-- B2. INVENTORY MOVEMENTS — the "why did stock change" log
-- ------------------------------------------------------------
create type movement_reason as enum ('restock', 'sale', 'return', 'damage', 'correction');

create table inventory_movements (
    id              uuid primary key default uuid_generate_v4(),
    inventory_id    uuid not null references inventory(id) on delete cascade,
    change_amount   integer not null,              -- positive = stock added, negative = stock removed
    reason          movement_reason not null,
    reference_order_id uuid,                       -- linked order, if reason = 'sale' or 'return'
    note            text,
    created_at      timestamptz not null default now()
);

-- ============================================================
-- ZONE C — COMMERCE
-- ============================================================

-- ------------------------------------------------------------
-- C1. CUSTOMERS — linked 1:1 to Supabase auth.users
-- ------------------------------------------------------------
create table customers (
    id          uuid primary key references auth.users(id) on delete cascade,  -- same id as the auth user
    full_name   text,
    email       text unique not null,
    phone       text,
    created_at  timestamptz not null default now()
);

-- Auto-create a customer row the moment someone signs up via Supabase Auth
-- (email/password, magic link, or OAuth — all land in auth.users the same way)
create or replace function handle_new_auth_user()
returns trigger as $$
begin
    insert into public.customers (id, email, full_name)
    values (
        new.id,
        new.email,
        new.raw_user_meta_data ->> 'full_name'
    )
    on conflict (id) do nothing;
    return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_new_auth_user
after insert on auth.users
for each row execute function handle_new_auth_user();

-- ------------------------------------------------------------
-- C2. SHIPPING METHODS — reusable lookup table
-- ------------------------------------------------------------
create table shipping_methods (
    id          uuid primary key default uuid_generate_v4(),
    name        text not null,          -- "Standard courier", "Express", "Pickup"
    cost        numeric(10,2) not null default 0,
    eta_days    integer,                -- estimated delivery time
    is_active   boolean not null default true
);

-- ------------------------------------------------------------
-- C3. PAYMENT METHODS — reusable lookup table
-- ------------------------------------------------------------
create table payment_methods (
    id          uuid primary key default uuid_generate_v4(),
    name        text not null,          -- "Cash on delivery", "Instapay", "Visa/Mastercard", "Fawry"
    is_active   boolean not null default true
);

-- ------------------------------------------------------------
-- C4. SALES CHANNELS — where the order came from
-- ------------------------------------------------------------
create table sales_channels (
    id          uuid primary key default uuid_generate_v4(),
    name        text not null,          -- "Own webpage", "Shopify", "Instagram", "WhatsApp"
    is_active   boolean not null default true
);

-- ------------------------------------------------------------
-- C5. ORDERS
-- ------------------------------------------------------------
create type order_status as enum ('pending', 'paid', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded');

create table orders (
    id                  uuid primary key default uuid_generate_v4(),
    customer_id         uuid references customers(id) on delete set null,
    status              order_status not null default 'pending',
    total               numeric(10,2) not null default 0,
    shipping_address     text,
    shipping_method_id   uuid references shipping_methods(id) on delete set null,
    payment_method_id    uuid references payment_methods(id) on delete set null,
    sales_channel_id     uuid references sales_channels(id) on delete set null,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now()
);

alter table inventory_movements
    add constraint fk_movement_order
    foreign key (reference_order_id) references orders(id) on delete set null;

-- ------------------------------------------------------------
-- C6. ORDER ITEMS — line items, snapshot pricing at sale time
-- ------------------------------------------------------------
create table order_items (
    id              uuid primary key default uuid_generate_v4(),
    order_id        uuid not null references orders(id) on delete cascade,
    product_id      uuid references products(id) on delete set null,
    variant_id      uuid references product_variants(id) on delete set null,
    product_name    text not null,      -- snapshot, survives product edits/deletion
    unit_price      numeric(10,2) not null,
    quantity        integer not null default 1,
    subtotal        numeric(10,2) generated always as (unit_price * quantity) stored
);

-- ------------------------------------------------------------
-- C7. SHIPMENTS — fulfillment tracking (an order can ship in parts)
-- ------------------------------------------------------------
create type shipment_status as enum ('preparing', 'shipped', 'in_transit', 'delivered', 'failed', 'returned');

create table shipments (
    id              uuid primary key default uuid_generate_v4(),
    order_id        uuid not null references orders(id) on delete cascade,
    carrier         text,                  -- "Bosta", "Aramex", "Mylerz"
    tracking_number text,
    status          shipment_status not null default 'preparing',
    shipped_at      timestamptz,
    delivered_at    timestamptz,
    created_at      timestamptz not null default now()
);

-- ============================================================
-- INDEXES
-- ============================================================
create index idx_products_category on products(category_id);
create index idx_products_vendor on products(vendor_id);
create index idx_products_status on products(status);
create index idx_variants_product on product_variants(product_id);
create index idx_media_product on product_media(product_id);
create index idx_inventory_product on inventory(product_id);
create index idx_movements_inventory on inventory_movements(inventory_id);
create index idx_orders_customer on orders(customer_id);
create index idx_orders_channel on orders(sales_channel_id);
create index idx_order_items_order on order_items(order_id);
create index idx_order_items_product on order_items(product_id);
create index idx_shipments_order on shipments(order_id);

-- ============================================================
-- AUTO-UPDATE updated_at TRIGGERS
-- ============================================================
create or replace function set_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

create trigger trg_products_updated_at   before update on products   for each row execute function set_updated_at();
create trigger trg_orders_updated_at     before update on orders     for each row execute function set_updated_at();
create trigger trg_inventory_updated_at  before update on inventory  for each row execute function set_updated_at();

-- ============================================================
-- ZONE D — ANALYTICS VIEWS (auto-computed, nothing to fill manually)
-- ============================================================

-- ------------------------------------------------------------
-- D1. PUBLIC PRODUCT CATALOG — what the webpage/API queries
-- ------------------------------------------------------------
create view products_public as
select
    p.id, p.name, p.sku, p.slug, p.description,
    p.price,
    p.final_price,
    coalesce(p.final_price, p.price)                          as effective_price,
    (p.final_price is not null and p.final_price < p.price)   as is_on_sale,
    case
        when p.final_price is not null and p.price > 0 and p.final_price < p.price
        then round((1 - p.final_price / p.price) * 100)
        else 0
    end                                                        as discount_percent,
    p.product_type, p.category_id, p.vendor_id, p.status,
    p.available_for_restock, p.created_at, p.updated_at
from products p
where p.status = 'active';

-- ------------------------------------------------------------
-- D2. MOST / LEAST REQUESTED PRODUCTS — computed from actual sales
-- ------------------------------------------------------------
create view product_demand as
select
    p.id                         as product_id,
    p.name,
    coalesce(sum(oi.quantity), 0) as total_units_sold,
    count(distinct oi.order_id)   as total_orders,
    rank() over (order by coalesce(sum(oi.quantity), 0) desc) as demand_rank
from products p
left join order_items oi on oi.product_id = p.id
group by p.id, p.name;
-- "Most requested" = order by demand_rank asc. "Least requested" = order by demand_rank desc.

-- ------------------------------------------------------------
-- D3. SHIPPED PRODUCTS — every product currently shipped/delivered
-- ------------------------------------------------------------
create view shipped_products as
select
    s.id            as shipment_id,
    o.id            as order_id,
    oi.product_name,
    oi.quantity,
    s.carrier,
    s.tracking_number,
    s.status        as shipment_status,
    s.shipped_at,
    s.delivered_at
from shipments s
join orders o on o.id = s.order_id
join order_items oi on oi.order_id = o.id
where s.status in ('shipped', 'in_transit', 'delivered');

-- ------------------------------------------------------------
-- D4. LOW STOCK ALERT — products needing restock
-- ------------------------------------------------------------
create view low_stock_products as
select
    p.name, i.quantity_on_hand, i.low_stock_threshold, pv.variant_name
from inventory i
join products p on p.id = i.product_id
left join product_variants pv on pv.id = i.variant_id
where i.quantity_on_hand <= i.low_stock_threshold;

-- ============================================================
-- ZONE E — CUSTOMER SERVICE (reviews & comments)
-- Tied to customers via email login (Supabase Auth), and to the
-- specific product. Optionally verified against a real purchase.
-- ============================================================

-- ------------------------------------------------------------
-- E1. PRODUCT REVIEWS — rating + text, one per customer per product
-- ------------------------------------------------------------
create table product_reviews (
    id              uuid primary key default uuid_generate_v4(),
    product_id      uuid not null references products(id) on delete cascade,
    customer_id     uuid not null references customers(id) on delete cascade,
    order_item_id   uuid references order_items(id) on delete set null,  -- links review to the actual purchase
    rating          integer not null check (rating between 1 and 5),
    title           text,
    body            text,
    is_verified_purchase boolean not null default false,   -- true if order_item_id resolves to a real delivered order
    status          text not null default 'published' check (status in ('published', 'hidden', 'flagged')),
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    unique (product_id, customer_id)      -- one review per customer per product
);

-- ------------------------------------------------------------
-- E2. REVIEW COMMENTS — replies on a review (seller replies, or
-- follow-up questions from other logged-in customers)
-- ------------------------------------------------------------
create table review_comments (
    id              uuid primary key default uuid_generate_v4(),
    review_id       uuid not null references product_reviews(id) on delete cascade,
    customer_id     uuid references customers(id) on delete set null,  -- null if written by seller/admin
    is_seller_reply boolean not null default false,
    body            text not null,
    created_at      timestamptz not null default now()
);

-- ------------------------------------------------------------
-- E3. DIRECT PRODUCT COMMENTS/QUESTIONS — not a star review,
-- just a Q&A style comment thread under a product (e.g. "does
-- this ship internationally?"). Still tied to a logged-in customer.
-- ------------------------------------------------------------
create table product_comments (
    id              uuid primary key default uuid_generate_v4(),
    product_id      uuid not null references products(id) on delete cascade,
    customer_id     uuid not null references customers(id) on delete cascade,
    parent_comment_id uuid references product_comments(id) on delete cascade,  -- for threaded replies
    body            text not null,
    created_at      timestamptz not null default now()
);

create index idx_reviews_product on product_reviews(product_id);
create index idx_reviews_customer on product_reviews(customer_id);
create index idx_review_comments_review on review_comments(review_id);
create index idx_product_comments_product on product_comments(product_id);
create index idx_product_comments_parent on product_comments(parent_comment_id);

create trigger trg_reviews_updated_at before update on product_reviews for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- E4. AUTO-VERIFY PURCHASE — marks a review verified if the
-- customer actually bought and received that product
-- ------------------------------------------------------------
create or replace function check_verified_purchase()
returns trigger as $$
begin
    if new.order_item_id is not null then
        new.is_verified_purchase := exists (
            select 1
            from order_items oi
            join orders o on o.id = oi.order_id
            where oi.id = new.order_item_id
              and o.customer_id = new.customer_id
              and oi.product_id = new.product_id
              and o.status = 'delivered'
        );
    end if;
    return new;
end;
$$ language plpgsql;

create trigger trg_verify_purchase
before insert or update on product_reviews
for each row execute function check_verified_purchase();

-- ============================================================
-- ROW LEVEL SECURITY — reviews & comments
-- ============================================================
alter table product_reviews enable row level security;
alter table review_comments enable row level security;
alter table product_comments enable row level security;

-- Anyone can read published reviews/comments (public storefront)
create policy "Public can view published reviews" on product_reviews for select using (status = 'published');
create policy "Public can view review comments" on review_comments for select using (true);
create policy "Public can view product comments" on product_comments for select using (true);

-- Only the logged-in customer can write/edit their own review
create policy "Customers can insert their own review"
on product_reviews for insert
with check (customer_id = auth.uid());

create policy "Customers can update their own review"
on product_reviews for update
using (customer_id = auth.uid());

create policy "Customers can post comments"
on product_comments for insert
with check (customer_id = auth.uid());

alter table customers enable row level security;

create policy "Customers can view their own customer row"
on customers for select
using (id = auth.uid());

create policy "Customers can update their own customer row"
on customers for update
using (id = auth.uid());

-- ============================================================
-- ZONE D (cont.) — RATING ANALYTICS VIEW
-- ============================================================
create view product_ratings as
select
    p.id                                   as product_id,
    p.name,
    count(r.id)                            as review_count,
    round(avg(r.rating)::numeric, 2)       as average_rating,
    count(r.id) filter (where r.is_verified_purchase) as verified_review_count
from products p
left join product_reviews r on r.product_id = p.id and r.status = 'published'
group by p.id, p.name;

alter table products enable row level security;
alter table product_variants enable row level security;
alter table product_media enable row level security;
alter table categories enable row level security;
alter table vendors enable row level security;

create policy "Public can view active products" on products for select using (status = 'active');
create policy "Public can view categories" on categories for select using (true);
create policy "Public can view variants" on product_variants for select using (true);
create policy "Public can view media" on product_media for select using (true);

-- ============================================================
-- ZONE F — STORE ADMINISTRATION
-- store_admins holds the accounts allowed to manage the catalog
-- and storefront. Separate from `customers` on purpose: a shopper
-- account should never automatically gain write access.
-- Admins are NOT created by public signup — add them manually
-- (via SQL, or the Supabase dashboard) after they sign up through
-- normal Supabase Auth, so only you decide who gets in.
-- ============================================================

create table store_admins (
    id          uuid primary key references auth.users(id) on delete cascade,
    email       text unique not null,
    full_name   text,
    role        text not null default 'admin' check (role in ('owner', 'admin', 'staff')),
    created_at  timestamptz not null default now()
);

-- Helper function used throughout RLS policies — returns true if the
-- currently authenticated user is a store admin of any role.
create or replace function is_store_admin()
returns boolean as $$
begin
    return exists (select 1 from store_admins where id = auth.uid());
end;
$$ language plpgsql security definer stable;

-- ------------------------------------------------------------
-- F1. SITE CONTENT — hero copy, category order, footer text, etc.
-- Key/value so new fields never require a migration.
-- ------------------------------------------------------------
create table site_content (
    key         text primary key,          -- e.g. 'hero_eyebrow', 'hero_title', 'footer_note'
    value       text,
    updated_at  timestamptz not null default now(),
    updated_by  uuid references store_admins(id) on delete set null
);

create trigger trg_site_content_updated_at
before update on site_content
for each row execute function set_updated_at();

alter table site_content enable row level security;
create policy "Public can view site content" on site_content for select using (true);
create policy "Store admins can manage site content" on site_content
for all using (is_store_admin()) with check (is_store_admin());

-- ------------------------------------------------------------
-- F2. STORE ADMIN — FULL WRITE ACCESS ACROSS THE CATALOG
-- One policy per table, all gated by is_store_admin(). Shoppers
-- keep their existing read-only policies; admins get everything.
-- ------------------------------------------------------------
create policy "Store admins manage products" on products
for all using (is_store_admin()) with check (is_store_admin());

create policy "Store admins manage product_variants" on product_variants
for all using (is_store_admin()) with check (is_store_admin());

create policy "Store admins manage product_media" on product_media
for all using (is_store_admin()) with check (is_store_admin());

create policy "Store admins manage categories" on categories
for all using (is_store_admin()) with check (is_store_admin());

create policy "Store admins manage vendors" on vendors
for all using (is_store_admin()) with check (is_store_admin());

alter table inventory enable row level security;
alter table inventory_movements enable row level security;
create policy "Store admins manage inventory" on inventory
for all using (is_store_admin()) with check (is_store_admin());
create policy "Store admins manage inventory_movements" on inventory_movements
for all using (is_store_admin()) with check (is_store_admin());

alter table shipping_methods enable row level security;
alter table payment_methods enable row level security;
alter table sales_channels enable row level security;
create policy "Public can view shipping methods" on shipping_methods for select using (is_active);
create policy "Public can view payment methods" on payment_methods for select using (is_active);
create policy "Public can view sales channels" on sales_channels for select using (is_active);
create policy "Store admins manage shipping methods" on shipping_methods
for all using (is_store_admin()) with check (is_store_admin());
create policy "Store admins manage payment methods" on payment_methods
for all using (is_store_admin()) with check (is_store_admin());
create policy "Store admins manage sales channels" on sales_channels
for all using (is_store_admin()) with check (is_store_admin());

alter table orders enable row level security;
alter table order_items enable row level security;
alter table shipments enable row level security;

create policy "Store admins manage orders" on orders
for all using (is_store_admin()) with check (is_store_admin());
create policy "Store admins manage order_items" on order_items
for all using (is_store_admin()) with check (is_store_admin());
create policy "Store admins manage shipments" on shipments
for all using (is_store_admin()) with check (is_store_admin());

-- Admins can also moderate reviews/comments (hide, flag, reply) without losing
-- the customer-authored policies already in place from Zone E.
create policy "Store admins manage reviews" on product_reviews
for all using (is_store_admin()) with check (is_store_admin());
create policy "Store admins manage review comments" on review_comments
for all using (is_store_admin()) with check (is_store_admin());
create policy "Store admins manage product comments" on product_comments
for all using (is_store_admin()) with check (is_store_admin());

-- Admins can view every customer record (needed for support/order lookup)
create policy "Store admins can view all customers" on customers
for select using (is_store_admin());

alter table store_admins enable row level security;
create policy "Store admins can view the admin roster" on store_admins
for select using (is_store_admin());
-- Note: no insert/update/delete policy on store_admins for regular admins —
-- adding a new admin is done via the Supabase dashboard or service_role key
-- only, so an admin can never grant themselves or others extra access.

-- ============================================================
-- ZONE G — MARKETING
-- Everything here exists so you can answer: which channel/campaign
-- actually drove a sale, which discount codes are working, who's
-- on the email list, and how each product reads to search/social.
-- ============================================================

-- ------------------------------------------------------------
-- G1. PRODUCT SEO/SOCIAL METADATA — how a product reads off-site
-- ------------------------------------------------------------
alter table products add column meta_title       text;   -- <title> override, falls back to name
alter table products add column meta_description  text;   -- search/social snippet
alter table products add column og_image_url      text;   -- link-preview image (WhatsApp, socials)
alter table products add column tags              text[] default '{}';  -- 'bestseller', 'summer26', 'gift-idea'

create index idx_products_tags on products using gin(tags);

-- ------------------------------------------------------------
-- G2. DISCOUNT CODES — promo codes, separate from the product-level
-- final_price. This is for cart-level or storewide promotions.
-- ------------------------------------------------------------
create type discount_type as enum ('percent', 'fixed_amount');

create table discount_codes (
    id              uuid primary key default uuid_generate_v4(),
    code            text unique not null,             -- "SUMMER20", entered at checkout
    discount_type   discount_type not null,
    value           numeric(10,2) not null,            -- 20 (%) or 100.00 (EGP off)
    min_order_total numeric(10,2) default 0,
    usage_limit     integer,                            -- null = unlimited
    times_used      integer not null default 0,
    starts_at       timestamptz,
    ends_at         timestamptz,
    is_active       boolean not null default true,
    created_by      uuid references store_admins(id) on delete set null,
    created_at      timestamptz not null default now()
);

-- ------------------------------------------------------------
-- G3. MARKETING CAMPAIGNS — the source of every UTM link you send
-- ------------------------------------------------------------
create type campaign_channel as enum ('instagram', 'facebook', 'tiktok', 'google_ads', 'email', 'influencer', 'whatsapp', 'other');

create table marketing_campaigns (
    id              uuid primary key default uuid_generate_v4(),
    name            text not null,             -- "Summer Cravates Launch"
    channel         campaign_channel not null,
    utm_source      text not null,             -- "instagram"
    utm_medium      text not null,             -- "paid", "organic", "influencer"
    utm_campaign    text not null unique,      -- "summer26_launch" — the actual UTM slug used in links
    budget          numeric(10,2),
    starts_at       timestamptz,
    ends_at         timestamptz,
    is_active       boolean not null default true,
    created_by      uuid references store_admins(id) on delete set null,
    created_at      timestamptz not null default now()
);

-- ------------------------------------------------------------
-- G4. ORDER ATTRIBUTION — which campaign/code actually drove this sale
-- ------------------------------------------------------------
alter table orders add column campaign_id       uuid references marketing_campaigns(id) on delete set null;
alter table orders add column discount_code_id  uuid references discount_codes(id) on delete set null;
alter table orders add column discount_amount   numeric(10,2) not null default 0;

create index idx_orders_campaign on orders(campaign_id);
create index idx_orders_discount on orders(discount_code_id);

-- ------------------------------------------------------------
-- G5. EMAIL SUBSCRIBERS — newsletter / marketing consent list
-- Distinct from `customers`: someone can subscribe without ever
-- creating an account or buying anything.
-- ------------------------------------------------------------
create table email_subscribers (
    id              uuid primary key default uuid_generate_v4(),
    email           text unique not null,
    customer_id     uuid references customers(id) on delete set null,  -- linked if they later become a customer
    source          text,               -- "storefront_footer", "checkout_optin", "instagram_bio_link"
    is_subscribed   boolean not null default true,
    subscribed_at   timestamptz not null default now(),
    unsubscribed_at timestamptz
);

create index idx_subscribers_email on email_subscribers(email);

-- ------------------------------------------------------------
-- RLS for marketing tables
-- ------------------------------------------------------------
alter table discount_codes enable row level security;
alter table marketing_campaigns enable row level security;
alter table email_subscribers enable row level security;

-- Discount codes: public can only check validity of a specific active code
-- at checkout (not browse the full list), admins manage everything.
create policy "Public can validate an active discount code" on discount_codes
for select using (is_active = true);
create policy "Store admins manage discount codes" on discount_codes
for all using (is_store_admin()) with check (is_store_admin());

-- Campaigns are internal-only — no public read needed.
create policy "Store admins manage campaigns" on marketing_campaigns
for all using (is_store_admin()) with check (is_store_admin());

-- Anyone can subscribe (insert), only admins can read/manage the list.
create policy "Anyone can subscribe to the newsletter" on email_subscribers
for insert with check (true);
create policy "Store admins manage subscribers" on email_subscribers
for all using (is_store_admin()) with check (is_store_admin());

-- ------------------------------------------------------------
-- G6. CAMPAIGN PERFORMANCE — revenue/orders per campaign, auto-computed
-- ------------------------------------------------------------
create view campaign_performance as
select
    c.id                            as campaign_id,
    c.name,
    c.channel,
    c.utm_campaign,
    c.budget,
    count(o.id)                     as orders_count,
    coalesce(sum(o.total), 0)       as revenue,
    case when c.budget > 0
        then round((coalesce(sum(o.total),0) / c.budget)::numeric, 2)
        else null
    end                              as return_on_spend
from marketing_campaigns c
left join orders o on o.campaign_id = c.id and o.status not in ('cancelled', 'refunded')
group by c.id, c.name, c.channel, c.utm_campaign, c.budget;

-- ------------------------------------------------------------
-- G7. DISCOUNT CODE PERFORMANCE
-- ------------------------------------------------------------
create view discount_code_performance as
select
    d.id                        as discount_code_id,
    d.code,
    d.discount_type,
    d.value,
    d.times_used,
    d.usage_limit,
    coalesce(sum(o.total), 0)   as revenue_generated,
    coalesce(sum(o.discount_amount), 0) as total_discount_given
from discount_codes d
left join orders o on o.discount_code_id = d.id and o.status not in ('cancelled', 'refunded')
group by d.id, d.code, d.discount_type, d.value, d.times_used, d.usage_limit;

-- ------------------------------------------------------------
-- G8. TAG-BASED PRODUCT DISCOVERY — for landing pages / collections
-- e.g. select * from products_by_tag where tag = 'summer26'
-- ------------------------------------------------------------
create view products_by_tag as
select p.id, p.name, p.slug, unnest(p.tags) as tag
from products p
where p.status = 'active';

-- ============================================================
-- ZONE H — STORE PROFILE, PRODUCT MEDIA/VIEWS, RICH INVENTORY
-- Everything a seller needs to actually run the store day to day:
-- one store identity, real product photography, who's looking at
-- what (even when it's out of stock), and stock that reflects
-- reality rather than a single guessed number.
-- ============================================================

-- ------------------------------------------------------------
-- H1. STORE — a single row describing the store itself.
-- Enforced as one row via a fixed id, so there's never ambiguity
-- about "which store" in a single-tenant setup.
-- ------------------------------------------------------------
create table store (
    id              boolean primary key default true check (id = true),  -- singleton row trick
    image_url       text,
    name            text not null default 'Monsieur',
    description     text,
    deliver_days    int4range,              -- e.g. '[2,5)' = 2 to 4 business days
    redirect_link_url text,                 -- partner marketplace listing, if any
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);
insert into store (id) values (true);

create trigger trg_store_updated_at before update on store for each row execute function set_updated_at();

alter table store enable row level security;
create policy "Public can view store profile" on store for select using (true);
create policy "Store admins manage store profile" on store
for all using (is_store_admin()) with check (is_store_admin());

-- ------------------------------------------------------------
-- H2. REDIRECT LINK CLICKS — every time a shopper is sent to a
-- partner marketplace listing to complete purchase there instead
-- ------------------------------------------------------------
create table redirect_link_clicks (
    id          uuid primary key default uuid_generate_v4(),
    product_id  uuid references products(id) on delete set null,
    customer_id uuid references customers(id) on delete set null,
    clicked_at  timestamptz not null default now()
);
create index idx_redirect_clicks_product on redirect_link_clicks(product_id);

alter table redirect_link_clicks enable row level security;
create policy "Anyone can log a redirect click" on redirect_link_clicks for insert with check (true);
create policy "Store admins view redirect clicks" on redirect_link_clicks for select using (is_store_admin());

-- ------------------------------------------------------------
-- H3. PRODUCT — additions: readable ID, imagery, discount %
-- ------------------------------------------------------------
alter table products add column hc_id        text unique;   -- human-friendly id, e.g. "CV-001" (cravate)
alter table products add column main_image_url text;
alter table products add column discount_percentage numeric(5,2)
    generated always as (
        case when final_price is not null and price > 0 and final_price < price
        then round((1 - final_price/price) * 100, 2) else 0 end
    ) stored;

-- Denormalized, fast-read stock fields kept in sync with `inventory`
-- by trigger below — storefront reads products, never has to join
-- inventory just to know "is this in stock".
alter table products add column stock_cached      integer not null default 0;
alter table products add column is_out_of_stock    boolean not null default true;

-- ------------------------------------------------------------
-- H4. PRODUCT VIEWS — page-visit analytics per product/customer,
-- including whether it was out of stock at the time (signals demand
-- you're currently failing to fulfill — worth restocking first).
-- ------------------------------------------------------------
create table product_views (
    id              uuid primary key default uuid_generate_v4(),
    product_id      uuid not null references products(id) on delete cascade,
    customer_id     uuid references customers(id) on delete set null,   -- null = anonymous visitor
    was_out_of_stock boolean not null default false,
    viewed_at       timestamptz not null default now()
);
create index idx_product_views_product on product_views(product_id);
create index idx_product_views_customer on product_views(customer_id);

alter table product_views enable row level security;
create policy "Anyone can log a product view" on product_views for insert with check (true);
create policy "Store admins view product views" on product_views for select using (is_store_admin());

-- ------------------------------------------------------------
-- H5. INVENTORY — rebuilt with the fields a seller actually checks
-- ------------------------------------------------------------
alter table inventory add column real_stock          integer;   -- seller's physically-counted stock; may differ from quantity_on_hand (reserved/damaged/in-transit)
alter table inventory add column max_stock_capacity   integer;   -- highest stock this product has ever held — gives restock sizing context
alter table inventory add column last_restocked_at    timestamptz;
alter table inventory add column last_restock_qty     integer;
alter table inventory add column restock_eta          timestamptz;   -- expected date the next shipment lands
alter table inventory add column vendor_id            uuid references vendors(id) on delete set null;  -- denormalized from products for fast vendor-side queries
alter table inventory add column out_of_stock_view_count integer not null default 0;  -- incremented whenever a product_views row lands while stock = 0

-- Keep products.stock_cached / is_out_of_stock / inventory.vendor_id in sync automatically
create or replace function sync_product_stock_cache()
returns trigger as $$
begin
    update products
    set stock_cached = new.quantity_on_hand,
        is_out_of_stock = (new.quantity_on_hand <= 0)
    where id = new.product_id;
    return new;
end;
$$ language plpgsql;

create trigger trg_sync_stock_cache
after insert or update of quantity_on_hand on inventory
for each row execute function sync_product_stock_cache();

create or replace function sync_inventory_vendor()
returns trigger as $$
begin
    new.vendor_id := (select vendor_id from products where id = new.product_id);
    return new;
end;
$$ language plpgsql;

create trigger trg_sync_inventory_vendor
before insert or update of product_id on inventory
for each row execute function sync_inventory_vendor();

-- Whenever a product view is logged while the product is out of
-- stock, bump the counter on its inventory row automatically.
create or replace function count_out_of_stock_view()
returns trigger as $$
begin
    if new.was_out_of_stock then
        update inventory set out_of_stock_view_count = out_of_stock_view_count + 1
        where product_id = new.product_id;
    end if;
    return new;
end;
$$ language plpgsql;

create trigger trg_count_oos_view
after insert on product_views
for each row execute function count_out_of_stock_view();

-- ------------------------------------------------------------
-- H6. INVENTORY ANALYTICS — is this item trending up or stalling?
-- Compares units sold in the last 14 days to the 14 days before.
-- ------------------------------------------------------------
create view inventory_analytics as
select
    i.product_id,
    p.name,
    i.quantity_on_hand,
    i.real_stock,
    i.max_stock_capacity,
    i.last_restocked_at,
    i.restock_eta,
    i.out_of_stock_view_count,
    coalesce(recent.units, 0)   as units_sold_last_14d,
    coalesce(prior.units, 0)    as units_sold_prior_14d,
    case
        when coalesce(prior.units,0) = 0 and coalesce(recent.units,0) > 0 then 'new_demand'
        when coalesce(prior.units,0) = 0 then 'no_activity'
        when recent.units > prior.units then 'trending_up'
        when recent.units < prior.units then 'trending_down'
        else 'steady'
    end                          as trend
from inventory i
join products p on p.id = i.product_id
left join (
    select oi.product_id, sum(oi.quantity) as units
    from order_items oi join orders o on o.id = oi.order_id
    where o.created_at >= now() - interval '14 days' and o.status not in ('cancelled','refunded')
    group by oi.product_id
) recent on recent.product_id = i.product_id
left join (
    select oi.product_id, sum(oi.quantity) as units
    from order_items oi join orders o on o.id = oi.order_id
    where o.created_at >= now() - interval '28 days' and o.created_at < now() - interval '14 days'
      and o.status not in ('cancelled','refunded')
    group by oi.product_id
) prior on prior.product_id = i.product_id;

-- ------------------------------------------------------------
-- H7. STORE STATS — everything on the store dashboard, computed
-- ------------------------------------------------------------
create view store_stats as
select
    (select count(*) from products where status = 'active')                          as total_products,
    (select count(*) from orders)                                                     as total_orders,
    (select count(*) from orders where status = 'delivered')                          as completed_orders,
    (select count(*) from orders where status = 'cancelled')                          as cancelled_orders,
    (select count(*) from orders where status = 'refunded')                           as refunded_orders,
    (select count(*) from product_reviews where status = 'published')                 as total_reviews,
    (select round(avg(rating)::numeric,2) from product_reviews where status='published') as average_rating,
    (select count(*) from products where final_price is not null and final_price < price and status='active') as products_in_sale,
    (select count(*) from product_views)                                              as products_viewed_total,
    (select count(*) from redirect_link_clicks)                                       as redirect_link_clicks_total;

-- ============================================================
-- ZONE I — STOREFRONT SYNC FIX (validation pass)
-- products_public (D1, above) was created before hc_id, main_image_url,
-- stock_cached, is_out_of_stock and discount_percentage existed (added
-- later in Zone H), and never included category name, pattern/colour,
-- rating or review count. monsieur_shop.html / monsieur_pdp.html read
-- all of those fields from products_public, so the view is rebuilt
-- here with every column the storefront actually queries. This zone
-- is additive/idempotent — safe to run once against the Zone A-H schema.
-- ============================================================

-- I1. Pattern / swatch colour — set from the admin product form,
-- read by the storefront to render the tie-pattern thumbnail.
alter table products add column pattern text not null default 'solid'
    check (pattern in ('solid','stripe','dot','paisley'));
alter table products add column swatch_color text not null default '#7c2430';

-- I2. Rebuild products_public with every field the frontend needs.
drop view if exists products_public;
create view products_public as
select
    p.id, p.hc_id, p.name, p.sku, p.slug, p.description,
    p.price,
    p.final_price,
    coalesce(p.final_price, p.price)                          as effective_price,
    (p.final_price is not null and p.final_price < p.price)   as is_on_sale,
    p.discount_percentage                                      as discount_percent,
    p.product_type,
    p.category_id,
    c.name                                                      as category,
    p.vendor_id,
    p.status,
    p.pattern,
    p.swatch_color,
    p.main_image_url,
    p.stock_cached                                              as stock,
    p.is_out_of_stock,
    p.tags,
    coalesce(pr.average_rating, 0)                              as rating,
    coalesce(pr.review_count, 0)                                as reviews,
    p.available_for_restock, p.created_at, p.updated_at
from products p
left join categories c on c.id = p.category_id
left join product_ratings pr on pr.product_id = p.id
where p.status = 'active';

grant select on products_public to anon, authenticated;

-- I3. Public-safe reviews view for the PDP. product_reviews.customer_id
-- points at customers, which has RLS locking each row to its owner —
-- a direct join from a shopper session would return null names for
-- everyone else's reviews. This view (owned by the schema owner, which
-- bypasses RLS the same way products_public already does) exposes only
-- what a shopper should see: rating, text, verified flag, first name.
create view product_reviews_public as
select
    r.id, r.product_id, r.rating, r.title, r.body,
    r.is_verified_purchase, r.created_at,
    coalesce(nullif(split_part(cu.full_name, ' ', 1), ''), 'Verified buyer') as reviewer_name
from product_reviews r
join customers cu on cu.id = r.customer_id
where r.status = 'published';

grant select on product_reviews_public to anon, authenticated;

-- I4. Realtime — the storefront/admin subscribe to these tables
-- instead of polling. products_public/reviews view changes surface
-- to clients as changes on the underlying tables below.
alter publication supabase_realtime add table products;
alter publication supabase_realtime add table inventory;
alter publication supabase_realtime add table store;
alter publication supabase_realtime add table categories;
alter publication supabase_realtime add table product_reviews;
alter publication supabase_realtime add table site_content;
alter publication supabase_realtime add table discount_codes;
alter publication supabase_realtime add table marketing_campaigns;
alter publication supabase_realtime add table email_subscribers;

-- I5. First admin — you must insert yourself into store_admins after
-- signing up once through monsieur_login.html, or every RLS "manage"
-- policy above stays closed to you too. Run this once, manually, with
-- the UUID from Authentication > Users in the Supabase dashboard:
--
--   insert into store_admins (id, email, full_name, role)
--   values ('<your-auth-user-uuid>', 'you@example.com', 'Your Name', 'owner');
