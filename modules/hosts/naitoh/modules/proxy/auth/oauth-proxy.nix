{ self, ... }:

{
  flake.modules.nixos.naitoh =
    { mv, config, ... }:
    {
      me.hostSecrets = {
        "oauth2-proxy/client_secret" = { };
        "oauth2-proxy/cookie_secret" = { };
      };

      services.oauth2-proxy = {
        enable = true;
        package = self.lib.withMainProgram "oauth2-proxy" mv.latest.oauth2-proxy;
        provider = "oidc";

        oidcIssuerUrl = config.me.services.pocket-id.url;

        clientID = "f7845688-52ff-4e45-a8d2-b197e14035be";
        clientSecretFile = config.sops.secrets."oauth2-proxy/client_secret".path;

        httpAddress = "http://127.0.0.1:4180";

        reverseProxy = true;
        trustedProxyIP = [ "127.0.0.1" ];

        email.addresses = "admin";

        scope = "openid profile";
        approvalPrompt = "auto";

        upstream = "static://200";
        passBasicAuth = false;
        setXauthrequest = true;

        cookie = {
          name = "__Host-oauth2_proxy";
          secretFile = config.sops.secrets."oauth2-proxy/cookie_secret".path;
          secure = true;
          httpOnly = true;
          expire = "24h";
          refresh = "0s";
        };

        extraConfig = {
          skip-provider-button = true;
          code-challenge-method = "S256";
          session-cookie-minimal = true;
          insecure-oidc-allow-unverified-email = true;
          oidc-email-claim = "preferred_username";
        };
      };
    };
}
