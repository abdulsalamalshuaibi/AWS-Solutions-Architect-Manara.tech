#!/bin/bash
set -xe

# تحديث النظام
yum update -y

# تثبيت وتفعيل Docker (Amazon Linux 2)
amazon-linux-extras install docker -y || true
systemctl enable docker
systemctl start docker
usermod -a -G docker ec2-user || true

# تشغيل عينة .NET جاهزة (تستمع على 80 داخل الحاوية)
# نربط منفذ 8080 على السيرفر إلى 80 داخل الحاوية
docker pull mcr.microsoft.com/dotnet/samples:aspnetapp
docker rm -f app || true
docker run -d --restart always --name app -p 8080:80 mcr.microsoft.com/dotnet/samples:aspnetapp

# صفحة صحّة اختيارية (Reverse proxy غير مستخدم حالياً؛ الـ ALB يفحص / على 8080)
echo "User data completed" > /var/log/user-data-done
