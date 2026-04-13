# Supabase Auth Setup Guide

Manual steps to complete in the Supabase dashboard before implementing auth in the iOS app.

---

## 1. Email OTP

1. Supabase Dashboard → **Authentication** (left sidebar) → **Providers**
2. Find **Email** — enable it
3. Disable **"Confirm email"** (this is the magic link option)
4. Enable **"OTP"** — Supabase will now send a 6-digit code instead of a link
5. Go to **Authentication → Settings**
6. Set **"Refresh Token Expiry"** to `2592000` (this is 30 days in seconds)
7. Optionally customise the OTP email template: **Authentication → Email Templates**

---

## 2. Apple Sign In

You need an Apple Developer account for this.

1. Supabase Dashboard → **Authentication → Providers → Apple** → enable it
2. Note the **redirect URL** Supabase shows you (looks like `https://<project-ref>.supabase.co/auth/v1/callback`) — you'll need it in the next steps
3. In your **Apple Developer account** (developer.apple.com):
   - Go to **Certificates, Identifiers & Profiles → Identifiers**
   - Create a new **Services ID** (e.g. `com.yourcompany.qwip.siwa`)
   - Enable **Sign In with Apple** on it
   - Click **Configure** and add the Supabase redirect URL as an allowed redirect URI
4. Still in Apple Developer → **Keys**:
   - Create a new key, enable **Sign In with Apple**, and associate it with your primary App ID
   - Download the `.p8` private key file (you can only download it once)
   - Note the **Key ID**
5. Back in Supabase → Apple provider, fill in:
   - **Team ID** (top right of your Apple Developer account)
   - **Key ID**
   - **Service ID** (the one you created above)
   - Paste the contents of the `.p8` file into the private key field

---

## 3. Google Sign In

You need a Google Cloud Console project for this.

1. Supabase Dashboard → **Authentication → Providers → Google** → enable it
2. Note the **redirect URL** Supabase shows you
3. In **Google Cloud Console** (console.cloud.google.com):
   - Go to **APIs & Services → Credentials**
   - Create an **OAuth 2.0 Client ID** — type: **Web application**
   - Add the Supabase redirect URL to the **Authorised redirect URIs**
   - Note the **Client ID** and **Client Secret** — these go into Supabase
   - Create a second **OAuth 2.0 Client ID** — type: **iOS**
   - Enter your app's **bundle ID** (e.g. `com.yourcompany.qwip`)
   - Note this **iOS Client ID** — this goes into the iOS app, not Supabase
4. Back in Supabase → Google provider, fill in:
   - **Client ID** (the Web application one)
   - **Client Secret** (the Web application one)

---

## Summary of credentials you'll collect

| Credential | Used in |
|---|---|
| Apple Team ID | Supabase dashboard |
| Apple Key ID | Supabase dashboard |
| Apple Service ID | Supabase dashboard |
| Apple `.p8` private key contents | Supabase dashboard |
| Google Web Client ID | Supabase dashboard |
| Google Web Client Secret | Supabase dashboard |
| Google iOS Client ID | iOS app (Info.plist / config) |
| Supabase project URL | iOS app |
| Supabase anon key | iOS app |
