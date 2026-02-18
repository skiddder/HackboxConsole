from flask import Flask  # Import the Flask class
import os
app = Flask(__name__)    # Create an instance of the class for our use
app.config['MAX_CONTENT_LENGTH'] = 64 * 1000 * 1000

from flask_login import LoginManager, UserMixin
login_manager = LoginManager()
login_manager.init_app(app)


app.secret_key = os.getenv("HACKBOX_SECRET_KEY", "superSecretHackboxKey")
app.config['SESSION_TYPE'] = 'filesystem'


@app.after_request
def add_security_headers(response):
    response.headers['Cross-Origin-Opener-Policy'] = 'same-origin'
    response.headers['Cross-Origin-Embedder-Policy'] = 'require-corp'
    return response


def sanitize_username(username : str) -> str:
    # just allow alphanumeric characters, underscores, dashes, @ and dots in the username
    return "".join([c for c in str(username) if c.isalnum() or c == "_" or c == "-" or c == "@" or c == "."]).strip()


class HackBoxUser(UserMixin):
    id = ""
    username = ""
    password = ""
    role = ""
    tenant = "Default"
    def __init__(self, username, password, role, tenant = "Default"):
        self.username = sanitize_username(username).lower()
        self.password = str(password)
        self.role = str(role).lower().strip()
        self.role = role if role in ["hacker", "coach", "techlead"] else "hacker"
        self.tenant = str(tenant).strip()
        self.id = sanitize_username(username).lower()

def create_all_users():
    allUsers = { }
    # get the directory of the current script
    userJson = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "users.json")
    if os.path.exists(userJson):
        import json
        with open(userJson, "r") as f:
            for usr in json.load(f):
                if "username" in usr and "password" in usr and "role" in usr:
                    if "tenant" in usr:
                        tenant = str(usr["tenant"]).strip()
                    else:
                        tenant = "Default"
                    role = str(usr["role"]).lower().strip()
                    if role not in ["hacker", "coach", "techlead"]:
                        role = "hacker"
                    print(f"Adding user {usr['username']} with role {role} and tenant {tenant}")
                    allUsers[sanitize_username(usr["username"]).lower()] = HackBoxUser(
                        str(usr["username"]),
                        str(usr["password"]),
                        role,
                        tenant
                    )
    # do not load the default users from the enviornment, if the user.json file exists
    if len(allUsers) > 0:
        print("Loaded users from users.json")
        return allUsers
    print("Loading users from environment variables (HACKBOX_HACKER_USER, HACKBOX_HACKER_PWD, HACKBOX_COACH_USER, HACKBOX_COACH_PWD)")
    allUsers[sanitize_username(os.getenv("HACKBOX_HACKER_USER", "hacker")).lower()] = HackBoxUser(
        os.getenv("HACKBOX_HACKER_USER", "hacker"),
        os.getenv("HACKBOX_HACKER_PWD", "hacker"),
        "hacker"
    )
    allUsers[sanitize_username(os.getenv("HACKBOX_COACH_USER", "coach")).lower()] = HackBoxUser(
        os.getenv("HACKBOX_COACH_USER", "coach"),
        os.getenv("HACKBOX_COACH_PWD", "coach"),
        "coach"
    )
    return allUsers

all_users = create_all_users()
all_tenants = set()
for user in all_users.values():
    # a tenant is only relevant for hackers and coaches (not for techleads)
    if user.role in ["hacker", "coach"]:
        all_tenants.add(user.tenant)
all_tenants = list(all_tenants)

@login_manager.user_loader
def loader_user(user_id):
    if user_id in all_users:
        return all_users[user_id]
    return None
