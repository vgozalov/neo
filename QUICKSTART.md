# Quick Start Guide

## 🎯 Deploy Everything in 5 Minutes

### Step 1: Prepare Information

Have these ready:
- [ ] Your domain name (e.g., `vagifgozalov.com`)
- [ ] Cloudflare email (e.g., `webmaster@avvaagency.com`)
- [ ] Cloudflare DNS API token ([Get it here](https://dash.cloudflare.com/profile/api-tokens))
- [ ] Desired admin username and password for Traefik

### Step 2: Run Deployment

```bash
cd /path/to/neo
./deploy.sh all
```

### Step 3: Answer Prompts

```
Enter your main domain [vagifgozalov.com]: yourdomain.com
Enter Cloudflare Email [webmaster@avvaagency.com]: your@email.com
Enter Cloudflare DNS API Token []: your_cloudflare_token_here
Enter Traefik Dashboard Username [admin]: admin
Enter Traefik Dashboard Password []: YourSecurePassword123
Enter Portainer Web UI Port [9000]: 9000
Enter Portainer Edge Agent Port [8000]: 8000
```

### Step 4: Configure DNS

In your Cloudflare dashboard, add:

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | traefik | YOUR_SERVER_IP | ✅ On |
| A | portainer | YOUR_SERVER_IP | ✅ On |

### Step 5: Access Your Services

Wait 2-3 minutes for SSL certificates, then visit:

- **Traefik Dashboard**: https://traefik.yourdomain.com
  - Username: (what you entered)
  - Password: (what you entered)

- **Portainer**: https://portainer.yourdomain.com
  - Set up admin account on first visit (within 5 minutes)

## 🎉 Done!

Your infrastructure is now running with:
- ✅ Automatic HTTPS/SSL
- ✅ Reverse proxy
- ✅ Docker management UI

## 📱 Quick Commands

```bash
# Check status
./deploy.sh status

# View logs
./deploy.sh logs traefik_traefik
./deploy.sh logs portainer_portainer

# Redeploy a service
./deploy.sh remove traefik
./deploy.sh traefik
```

## ⚠️ Important Notes

1. **Portainer Admin**: Set up admin credentials within 5 minutes of first deployment
2. **DNS Propagation**: May take a few minutes for DNS changes to propagate
3. **SSL Certificates**: First certificate generation may take 1-2 minutes
4. **Firewall**: Ensure ports 80, 443, 9000, 8000 are open

## 🆘 Quick Troubleshooting

**Can't access services?**
```bash
# Check if services are running
docker service ls

# Check logs
./deploy.sh logs traefik_traefik
```

**DNS not resolving?**
```bash
# Test DNS
dig traefik.yourdomain.com
dig portainer.yourdomain.com
```

**Port conflicts?**
```bash
# Check what's using port 80/443
sudo netstat -tulpn | grep -E ':80|:443'
```

---

For detailed documentation, see [README.md](README.md)

